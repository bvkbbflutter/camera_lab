'use strict';

/**
 * Detect the REAL image format from magic bytes.
 * The client-provided MIME type / extension is never trusted on its own.
 */

const FORMATS = Object.freeze({
  jpeg: { mimeType: 'image/jpeg', extensions: ['jpg', 'jpeg'], ext: 'jpg' },
  png: { mimeType: 'image/png', extensions: ['png'], ext: 'png' },
  webp: { mimeType: 'image/webp', extensions: ['webp'], ext: 'webp' },
});

function sniffFormat(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47 &&
    buf[4] === 0x0d && buf[5] === 0x0a && buf[6] === 0x1a && buf[7] === 0x0a
  ) return 'png';
  if (buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  return null;
}

function formatFromMime(mime) {
  if (!mime) return null;
  const m = String(mime).toLowerCase().split(';')[0].trim();
  if (m === 'image/jpeg' || m === 'image/jpg') return 'jpeg';
  if (m === 'image/png') return 'png';
  if (m === 'image/webp') return 'webp';
  return null;
}

function formatFromFileName(name) {
  if (!name) return null;
  const ext = String(name).toLowerCase().split('.').pop();
  for (const [fmt, def] of Object.entries(FORMATS)) {
    if (def.extensions.includes(ext)) return fmt;
  }
  return null;
}

module.exports = { FORMATS, sniffFormat, formatFromMime, formatFromFileName };
