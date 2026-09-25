'use strict';

/**
 * Container parsers — read the ACTUAL pixel dimensions from the bitstream
 * headers and locate the embedded EXIF block, without decoding pixels.
 *
 *   JPEG : SOFn marker for dimensions, APP1 "Exif\0\0" for EXIF, APP0 JFIF for density
 *   PNG  : IHDR for dimensions, eXIf chunk for EXIF, pHYs chunk for density
 *   WebP : VP8 / VP8L / VP8X for dimensions, EXIF chunk for EXIF
 */

const SOF_MARKERS = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);

function parseJpeg(buf) {
  const out = {
    width: null, height: null, exif: null, metadataBytes: 0,
    jfif: null, progressive: false, segments: [],
  };
  let o = 2; // after SOI
  while (o + 4 <= buf.length) {
    if (buf[o] !== 0xff) throw new Error(`JPEG: expected marker at offset ${o}`);
    let marker = buf[o + 1];
    while (marker === 0xff && o + 2 < buf.length) { o++; marker = buf[o + 1]; } // fill bytes
    o += 2;
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (marker === 0xd9) break; // EOI
    const len = buf.readUInt16BE(o);
    if (len < 2 || o + len > buf.length) throw new Error('JPEG: truncated segment');
    const data = buf.subarray(o + 2, o + len);
    out.segments.push({ marker, length: len + 2 });

    if (marker === 0xe1 && data.length >= 6 && data.toString('latin1', 0, 6) === 'Exif\0\0') {
      if (!out.exif) out.exif = data.subarray(6);
      out.metadataBytes += len + 2;
    } else if (marker === 0xe1 || marker === 0xed || marker === 0xe2) {
      out.metadataBytes += len + 2; // XMP / IPTC / ICC also count as metadata
    } else if (marker === 0xe0 && data.length >= 12 && data.toString('latin1', 0, 5) === 'JFIF\0') {
      const units = data[7];
      out.jfif = {
        version: `${data[5]}.${String(data[6]).padStart(2, '0')}`,
        units: units === 1 ? 'inch' : units === 2 ? 'cm' : 'aspect-ratio-only',
        xDensity: data.readUInt16BE(8),
        yDensity: data.readUInt16BE(10),
      };
    } else if (SOF_MARKERS.has(marker) && data.length >= 5) {
      out.height = data.readUInt16BE(1);
      out.width = data.readUInt16BE(3);
      out.progressive = marker === 0xc2 || marker === 0xc6 || marker === 0xca || marker === 0xce;
    }
    if (marker === 0xda) break; // SOS — entropy-coded data follows
    o += len;
  }
  if (!out.width || !out.height) throw new Error('JPEG: no SOF marker (not a decodable JPEG)');
  return out;
}

function parsePng(buf) {
  const out = { width: null, height: null, exif: null, metadataBytes: 0, phys: null, text: {} };
  let o = 8;
  let first = true;
  while (o + 12 <= buf.length) {
    const len = buf.readUInt32BE(o);
    const type = buf.toString('latin1', o + 4, o + 8);
    if (o + 12 + len > buf.length) throw new Error('PNG: truncated chunk');
    const data = buf.subarray(o + 8, o + 8 + len);
    if (first && type !== 'IHDR') throw new Error('PNG: first chunk is not IHDR');
    first = false;
    if (type === 'IHDR') {
      out.width = data.readUInt32BE(0);
      out.height = data.readUInt32BE(4);
    } else if (type === 'eXIf') {
      if (!out.exif) out.exif = data;
      out.metadataBytes += 12 + len;
    } else if (type === 'pHYs' && len === 9) {
      out.phys = { xPpu: data.readUInt32BE(0), yPpu: data.readUInt32BE(4), unit: data[8] === 1 ? 'meter' : 'unknown' };
      out.metadataBytes += 12 + len;
    } else if (type === 'tEXt') {
      const nul = data.indexOf(0);
      if (nul > 0) out.text[data.toString('latin1', 0, nul)] = data.toString('latin1', nul + 1);
      out.metadataBytes += 12 + len;
    } else if (type === 'iTXt' || type === 'zTXt' || type === 'iCCP') {
      out.metadataBytes += 12 + len;
    } else if (type === 'IEND') {
      break;
    }
    o += 12 + len;
  }
  if (!out.width || !out.height) throw new Error('PNG: missing IHDR');
  return out;
}

function parseWebp(buf) {
  const out = {
    width: null, height: null, exif: null, metadataBytes: 0,
    encoding: null, extended: false, flags: null, chunks: [],
  };
  let o = 12;
  while (o + 8 <= buf.length) {
    const type = buf.toString('latin1', o, o + 4);
    const len = buf.readUInt32LE(o + 4);
    if (o + 8 + len > buf.length) throw new Error('WebP: truncated chunk');
    const data = buf.subarray(o + 8, o + 8 + len);
    out.chunks.push(type);
    if (type === 'VP8X' && len >= 10) {
      out.extended = true;
      const f = data[0];
      out.flags = {
        icc: !!(f & 0x20), alpha: !!(f & 0x10), exif: !!(f & 0x08), xmp: !!(f & 0x04), animation: !!(f & 0x02),
      };
      out.width = 1 + data.readUIntLE(4, 3);
      out.height = 1 + data.readUIntLE(7, 3);
    } else if (type === 'VP8 ' && len >= 10) {
      out.encoding = 'lossy';
      if (data[3] !== 0x9d || data[4] !== 0x01 || data[5] !== 0x2a) throw new Error('WebP: bad VP8 start code');
      if (!out.width) {
        out.width = data.readUInt16LE(6) & 0x3fff;
        out.height = data.readUInt16LE(8) & 0x3fff;
      }
    } else if (type === 'VP8L' && len >= 5) {
      out.encoding = 'lossless';
      if (data[0] !== 0x2f) throw new Error('WebP: bad VP8L signature');
      if (!out.width) {
        const bits = data.readUInt32LE(1);
        out.width = (bits & 0x3fff) + 1;
        out.height = ((bits >>> 14) & 0x3fff) + 1;
      }
    } else if (type === 'EXIF') {
      if (!out.exif) out.exif = data;
      out.metadataBytes += 8 + len + (len & 1);
    } else if (type === 'XMP ' || type === 'ICCP') {
      out.metadataBytes += 8 + len + (len & 1);
    }
    o += 8 + len + (len & 1); // chunks are padded to even size
  }
  if (!out.width || !out.height) throw new Error('WebP: no image chunk');
  return out;
}

function parseContainer(format, buf) {
  if (format === 'jpeg') return parseJpeg(buf);
  if (format === 'png') return parsePng(buf);
  if (format === 'webp') return parseWebp(buf);
  throw new Error(`Unsupported format ${format}`);
}

module.exports = { parseJpeg, parsePng, parseWebp, parseContainer };
