'use strict';

const crypto = require('crypto');
const path = require('path');
const config = require('../config');
const { inspectImage } = require('./inspect');
const { FORMATS } = require('./sniff');

class ValidationError extends Error {
  constructor(message, code = 'VALIDATION_ERROR', status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** Validate size/dimensions and inspect the actual bytes. Throws ValidationError. */
function validateAndInspect(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new ValidationError('Empty file', 'EMPTY_FILE');
  }
  if (buffer.length > config.maxFileBytes) {
    throw new ValidationError(
      `File is ${(buffer.length / 1e6).toFixed(1)} MB, exceeds the ${config.maxFileBytes / 1e6} MB limit`,
      'FILE_TOO_LARGE', 413,
    );
  }

  const info = inspectImage(buffer); // throws for unsupported/corrupt

  if (info.width > config.maxDimension || info.height > config.maxDimension) {
    throw new ValidationError(
      `Image dimensions ${info.width}x${info.height} exceed the ${config.maxDimension}px limit`,
      'DIMENSIONS_TOO_LARGE',
    );
  }
  if (info.width * info.height > config.maxPixels) {
    throw new ValidationError(`Image has too many pixels (${info.megapixels} MP)`, 'TOO_MANY_PIXELS');
  }

  return info;
}

/**
 * Persist a validated image + build its db.json record.
 * @param {{ storage, db }} deps
 */
async function storeImage(deps, { buffer, info, originalFileName, uploadMethod, uploadId, userId, clientMimeType }) {
  const id = crypto.randomUUID();
  const ext = FORMATS[info.format].ext;
  const key = path.posix.join(info.format, `${id}.${ext}`);

  const { sizeBytes } = await deps.storage.put(key, buffer);

  const record = {
    id,
    fileName: originalFileName || `${id}.${ext}`,
    storageKey: key,
    // Relative path under the server root — this is what "assets/jpeg/xxx.jpg" looks like on disk.
    assetPath: deps.storage.publicPath(key),
    mimeType: info.mimeType,
    clientMimeType: clientMimeType || null,
    format: info.format,
    width: info.width,
    height: info.height,
    fileSizeBytes: sizeBytes,
    uploadMethod, // 'base64' | 'multipart'
    uploadId: uploadId || null,
    userId: userId || null,
    uploadedAt: new Date().toISOString(),

    // ---- derived/indexed metadata, extracted FROM the image itself ----
    exifPresent: info.exifPresent,
    exifSizeBytes: info.exifSizeBytes,
    metadataBytes: info.metadataBytes,
    latitude: info.gps ? info.gps.latitude : null,
    longitude: info.gps ? info.gps.longitude : null,
    altitude: info.gps ? info.gps.altitude : null,
    capturedAt: info.capture ? info.capture.capturedAt : null,
    cameraMake: info.camera ? info.camera.make : null,
    cameraModel: info.camera ? info.camera.model : null,
    orientation: info.orientation ? info.orientation.value : null,
    dpiX: info.dpi ? info.dpi.x : null,
    dpiY: info.dpi ? info.dpi.y : null,
  };

  await deps.db.insertImage(record);
  return record;
}

function toSummaryJson(record, baseUrl) {
  return {
    id: record.id,
    fileName: record.fileName,
    format: record.format,
    mimeType: record.mimeType,
    width: record.width,
    height: record.height,
    fileSizeBytes: record.fileSizeBytes,
    uploadMethod: record.uploadMethod,
    uploadedAt: record.uploadedAt,
    exifPresent: record.exifPresent,
    hasGps: record.latitude !== null && record.longitude !== null,
    url: `${baseUrl}/api/images/${record.id}`,
    metadataUrl: `${baseUrl}/api/images/${record.id}/metadata`,
  };
}

module.exports = { ValidationError, validateAndInspect, storeImage, toSummaryJson };
