'use strict';

/**
 * Inspect an uploaded image file:
 *
 *   Uploaded file → real format → dimensions → EXIF → GPS → date/time
 *                → camera → orientation → DPI
 *
 * The result is a DERIVED representation of what is embedded in the file.
 * It never replaces the metadata inside the image.
 */

const { sniffFormat, FORMATS } = require('./sniff');
const { parseContainer } = require('./containers');
const { parseTiff, tiffToMetadata } = require('./tiff');

const INCH_PER_METER = 0.0254;

function inspectImage(buf) {
  const format = sniffFormat(buf);
  if (!format) {
    const err = new Error('File is not a JPEG, PNG or WebP image');
    err.status = 415;
    err.code = 'UNSUPPORTED_FORMAT';
    throw err;
  }

  let container;
  try {
    container = parseContainer(format, buf);
  } catch (e) {
    const err = new Error(`Corrupt ${format.toUpperCase()} file: ${e.message}`);
    err.status = 400;
    err.code = 'CORRUPT_IMAGE';
    throw err;
  }

  let exifMeta = null;
  let exifError = null;
  if (container.exif && container.exif.length >= 8) {
    try {
      exifMeta = tiffToMetadata(parseTiff(container.exif));
    } catch (e) {
      exifError = e.message; // bad EXIF must not reject an otherwise valid image
    }
  }

  // DPI: EXIF XResolution first, then the container's native density field.
  let dpi = null;
  const r = exifMeta && exifMeta.resolution;
  if (r && r.xResolution && (r.resolutionUnit === 'inch' || r.resolutionUnit === 'cm')) {
    const k = r.resolutionUnit === 'cm' ? 2.54 : 1;
    dpi = { x: round2(r.xResolution * k), y: round2((r.yResolution ?? r.xResolution) * k), source: 'exif' };
  } else if (format === 'jpeg' && container.jfif && container.jfif.units !== 'aspect-ratio-only') {
    const k = container.jfif.units === 'cm' ? 2.54 : 1;
    dpi = { x: round2(container.jfif.xDensity * k), y: round2(container.jfif.yDensity * k), source: 'jfif' };
  } else if (format === 'png' && container.phys && container.phys.unit === 'meter') {
    dpi = { x: round2(container.phys.xPpu * INCH_PER_METER), y: round2(container.phys.yPpu * INCH_PER_METER), source: 'pHYs' };
  }

  const nativeDensity = format === 'jpeg' ? container.jfif
    : format === 'png' ? (container.phys ? {
      ...container.phys,
      dpiX: round2(container.phys.xPpu * INCH_PER_METER),
      dpiY: round2(container.phys.yPpu * INCH_PER_METER),
    } : null)
      : null; // WebP has no native density field — EXIF only

  return {
    format,
    mimeType: FORMATS[format].mimeType,
    width: container.width,
    height: container.height,
    megapixels: round2((container.width * container.height) / 1e6),
    fileSizeBytes: buf.length,
    exifPresent: !!exifMeta,
    exifSizeBytes: container.exif ? container.exif.length : 0,
    metadataBytes: container.metadataBytes,
    exifError,
    gps: exifMeta ? exifMeta.gps : null,
    capture: exifMeta ? exifMeta.capture : null,
    camera: exifMeta ? exifMeta.camera : null,
    orientation: exifMeta ? exifMeta.orientation : null,
    dpi,
    exifResolution: exifMeta ? exifMeta.resolution : null,
    nativeDensity,
    formatDetails: format === 'webp'
      ? { encoding: container.encoding, extended: container.extended, flags: container.flags, chunks: container.chunks }
      : format === 'jpeg'
        ? { progressive: container.progressive }
        : { textChunks: Object.keys(container.text) },
  };
}

function round2(n) {
  return typeof n === 'number' && Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}

module.exports = { inspectImage };
