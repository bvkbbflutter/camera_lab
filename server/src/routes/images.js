'use strict';

const express = require('express');
const multer = require('multer');
const config = require('../config');
const { formatFromMime, formatFromFileName } = require('../image/sniff');
const { ValidationError, validateAndInspect, storeImage, toSummaryJson } = require('../image/imageService');

const MAX_BASE64_CHARS = Math.ceil(config.maxFileBytes / 3) * 4 + 1024;

/**
 * @param {{ storage: import('../storage/LocalStorageService').LocalStorageService, db: import('../db/jsonDb').JsonDb }} deps
 */
function imagesRouter(deps) {
  const router = express.Router();

  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: config.maxFileBytes, files: 1 },
    fileFilter(req, file, cb) {
      // Cheap pre-filter on client-declared type/extension. The bytes are the
      // real check, done in validateAndInspect() once the buffer is in hand.
      const byMime = formatFromMime(file.mimetype);
      const byExt = formatFromFileName(file.originalname);
      if (!byMime && !byExt) {
        return cb(new ValidationError(
          `Unsupported file type (mimetype="${file.mimetype}", name="${file.originalname}")`,
          'UNSUPPORTED_FORMAT', 415,
        ));
      }
      cb(null, true);
    },
  });

  function baseUrl(req) {
    return `${req.protocol}://${req.get('host')}`;
  }

  // ---- POST /api/images/base64 --------------------------------------------
  router.post('/images/base64', express.json({ limit: config.maxJsonBytes }), async (req, res, next) => {
    try {
      const { fileName, mimeType, imageBase64, uploadId, userId } = req.body || {};

      if (!imageBase64 || typeof imageBase64 !== 'string') {
        throw new ValidationError('"imageBase64" is required and must be a string', 'MISSING_IMAGE_BASE64');
      }
      if (imageBase64.length > MAX_BASE64_CHARS) {
        throw new ValidationError('imageBase64 payload exceeds the configured size limit', 'FILE_TOO_LARGE', 413);
      }

      // Accept a data: URI prefix if the client sent one, but don't require it.
      const commaIdx = imageBase64.indexOf(',');
      const b64 = imageBase64.startsWith('data:') && commaIdx !== -1 ? imageBase64.slice(commaIdx + 1) : imageBase64;

      if (!/^[A-Za-z0-9+/]+={0,2}$/.test(b64.replace(/\s/g, ''))) {
        throw new ValidationError('imageBase64 is not valid Base64', 'INVALID_BASE64');
      }

      let buffer;
      try {
        buffer = Buffer.from(b64, 'base64');
      } catch {
        throw new ValidationError('imageBase64 could not be decoded', 'INVALID_BASE64');
      }
      if (buffer.length === 0) throw new ValidationError('Decoded image is empty', 'EMPTY_FILE');

      const info = validateAndInspect(buffer);
      const record = await storeImage(deps, {
        buffer, info, originalFileName: fileName, uploadMethod: 'base64', uploadId, userId, clientMimeType: mimeType,
      });

      res.status(201).json({ success: true, fileId: record.id, image: toSummaryJson(record, baseUrl(req)) });
    } catch (err) {
      next(err);
    }
  });

  // ---- POST /api/images/multipart -----------------------------------------
  router.post('/images/multipart', upload.single('file'), async (req, res, next) => {
    try {
      if (!req.file) throw new ValidationError('Missing "file" field in multipart/form-data body', 'MISSING_FILE');

      const { uploadId, userId } = req.body || {};
      const info = validateAndInspect(req.file.buffer);
      const record = await storeImage(deps, {
        buffer: req.file.buffer,
        info,
        originalFileName: req.file.originalname,
        uploadMethod: 'multipart',
        uploadId,
        userId,
        clientMimeType: req.file.mimetype,
      });

      res.status(201).json({ success: true, fileId: record.id, image: toSummaryJson(record, baseUrl(req)) });
    } catch (err) {
      next(err);
    }
  });

  // ---- GET /api/images (list, paginated) ----------------------------------
  router.get('/images', (req, res) => {
    const limit = Math.min(Number.parseInt(req.query.limit, 10) || 50, 200);
    const offset = Math.max(Number.parseInt(req.query.offset, 10) || 0, 0);
    const { total, items } = deps.db.listImages({ limit, offset });
    res.json({
      success: true,
      total,
      limit,
      offset,
      images: items.map((r) => toSummaryJson(r, baseUrl(req))),
    });
  });

  // ---- GET /api/images/:id (binary) ---------------------------------------
  router.get('/images/:id', async (req, res, next) => {
    try {
      const record = deps.db.getImage(req.params.id);
      if (!record) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Image not found' } });

      if (!(await deps.storage.exists(record.storageKey))) {
        return res.status(404).json({ success: false, error: { code: 'FILE_MISSING', message: 'Image record exists but the file is missing on disk' } });
      }

      res.setHeader('Content-Type', record.mimeType);
      res.setHeader('Content-Disposition', `inline; filename="${record.fileName.replace(/"/g, '')}"`);
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      const stream = await deps.storage.getStream(record.storageKey);
      stream.on('error', next);
      stream.pipe(res);
    } catch (err) {
      next(err);
    }
  });

  // ---- GET /api/images/:id/metadata ---------------------------------------
  router.get('/images/:id/metadata', async (req, res, next) => {
    try {
      const record = deps.db.getImage(req.params.id);
      if (!record) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Image not found' } });

      // Re-inspect the file itself on every call — the image is the source of
      // truth, db.json is only a cached index alongside it.
      const buffer = await deps.storage.getBuffer(record.storageKey);
      const { inspectImage } = require('../image/inspect');
      const info = inspectImage(buffer);

      res.json({
        success: true,
        fileId: record.id,
        source: 'embedded-in-image',
        metadata: {
          format: info.format,
          mimeType: info.mimeType,
          width: info.width,
          height: info.height,
          fileSizeBytes: info.fileSizeBytes,
          exif: {
            present: info.exifPresent,
            sizeBytes: info.exifSizeBytes,
            error: info.exifError,
          },
          metadataBytes: info.metadataBytes,
          gps: info.gps,
          capture: info.capture,
          camera: info.camera,
          orientation: info.orientation,
          dpi: info.dpi,
          nativeDensity: info.nativeDensity,
          exifResolution: info.exifResolution,
          formatDetails: info.formatDetails,
        },
        // What's in db.json for this record — an indexed CACHE of the above, not authoritative.
        indexed: {
          latitude: record.latitude,
          longitude: record.longitude,
          altitude: record.altitude,
          capturedAt: record.capturedAt,
          cameraMake: record.cameraMake,
          cameraModel: record.cameraModel,
          orientation: record.orientation,
          dpiX: record.dpiX,
          dpiY: record.dpiY,
        },
      });
    } catch (err) {
      next(err);
    }
  });

  // ---- DELETE /api/images/:id ----------------------------------------------
  router.delete('/images/:id', async (req, res, next) => {
    try {
      const record = deps.db.getImage(req.params.id);
      if (!record) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Image not found' } });
      await deps.storage.delete(record.storageKey);
      await deps.db.deleteImage(req.params.id);
      res.json({ success: true, deletedId: req.params.id });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

module.exports = { imagesRouter };
