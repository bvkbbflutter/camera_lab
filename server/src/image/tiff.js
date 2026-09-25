'use strict';

/**
 * Minimal, dependency-free TIFF/EXIF parser.
 *
 * Input: the raw TIFF block that EXIF is stored as
 *   - JPEG: APP1 payload after "Exif\0\0"
 *   - PNG : eXIf chunk data
 *   - WebP: EXIF chunk data (optionally prefixed with "Exif\0\0")
 *
 * Reads IFD0, the Exif sub-IFD (0x8769) and the GPS sub-IFD (0x8825).
 * Handles both byte orders ("II" little-endian, "MM" big-endian).
 */

const TYPE_SIZE = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8 };

const TAGS = Object.freeze({
  // IFD0
  ImageWidth: 0x0100,
  ImageLength: 0x0101,
  Make: 0x010f,
  Model: 0x0110,
  Orientation: 0x0112,
  XResolution: 0x011a,
  YResolution: 0x011b,
  ResolutionUnit: 0x0128,
  Software: 0x0131,
  DateTime: 0x0132,
  ExifIFD: 0x8769,
  GPSIFD: 0x8825,
  // Exif IFD
  ExposureTime: 0x829a,
  FNumber: 0x829d,
  ISO: 0x8827,
  ExifVersion: 0x9000,
  DateTimeOriginal: 0x9003,
  DateTimeDigitized: 0x9004,
  OffsetTime: 0x9010,
  OffsetTimeOriginal: 0x9011,
  SubSecTimeOriginal: 0x9291,
  FocalLength: 0x920a,
  PixelXDimension: 0xa002,
  PixelYDimension: 0xa003,
  LensMake: 0xa433,
  LensModel: 0xa434,
  // GPS IFD
  GPSVersionID: 0x0000,
  GPSLatitudeRef: 0x0001,
  GPSLatitude: 0x0002,
  GPSLongitudeRef: 0x0003,
  GPSLongitude: 0x0004,
  GPSAltitudeRef: 0x0005,
  GPSAltitude: 0x0006,
  GPSTimeStamp: 0x0007,
  GPSDateStamp: 0x001d,
  GPSHPositioningError: 0x001f,
});

class Reader {
  constructor(buf) {
    this.buf = buf;
    const order = buf.toString('ascii', 0, 2);
    if (order === 'II') this.le = true;
    else if (order === 'MM') this.le = false;
    else throw new Error('Not a TIFF block (bad byte order mark)');
    if (this.u16(2) !== 42) throw new Error('Not a TIFF block (magic != 42)');
  }
  u8(o) { return this.buf.readUInt8(o); }
  u16(o) { return this.le ? this.buf.readUInt16LE(o) : this.buf.readUInt16BE(o); }
  u32(o) { return this.le ? this.buf.readUInt32LE(o) : this.buf.readUInt32BE(o); }
  i16(o) { return this.le ? this.buf.readInt16LE(o) : this.buf.readInt16BE(o); }
  i32(o) { return this.le ? this.buf.readInt32LE(o) : this.buf.readInt32BE(o); }
}

function readValue(r, type, count, valueOffset) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const sz = TYPE_SIZE[type];
    const o = valueOffset + i * sz;
    switch (type) {
      case 1: case 7: out.push(r.u8(o)); break;
      case 6: out.push(r.buf.readInt8(o)); break;
      case 2: out.push(r.u8(o)); break;
      case 3: out.push(r.u16(o)); break;
      case 8: out.push(r.i16(o)); break;
      case 4: out.push(r.u32(o)); break;
      case 9: out.push(r.i32(o)); break;
      case 5: out.push([r.u32(o), r.u32(o + 4)]); break;
      case 10: out.push([r.i32(o), r.i32(o + 4)]); break;
      case 11: out.push(r.le ? r.buf.readFloatLE(o) : r.buf.readFloatBE(o)); break;
      case 12: out.push(r.le ? r.buf.readDoubleLE(o) : r.buf.readDoubleBE(o)); break;
      default: return null;
    }
  }
  if (type === 2) {
    // ASCII: strip trailing NULs
    let s = Buffer.from(out).toString('latin1');
    const nul = s.indexOf('\0');
    if (nul !== -1) s = s.slice(0, nul);
    return s.trim();
  }
  return out;
}

function readIfd(r, offset, seen) {
  const entries = new Map();
  if (!offset || offset + 2 > r.buf.length || seen.has(offset)) return entries;
  seen.add(offset);
  const n = r.u16(offset);
  for (let i = 0; i < n; i++) {
    const e = offset + 2 + i * 12;
    if (e + 12 > r.buf.length) break;
    const tag = r.u16(e);
    const type = r.u16(e + 2);
    const count = r.u32(e + 4);
    const size = TYPE_SIZE[type];
    if (!size) continue;
    const total = size * count;
    const valueOffset = total <= 4 ? e + 8 : r.u32(e + 8);
    if (valueOffset + total > r.buf.length) continue; // corrupt entry, skip
    const value = readValue(r, type, count, valueOffset);
    if (value !== null) entries.set(tag, { tag, type, count, value });
  }
  return entries;
}

/**
 * @param {Buffer} tiff
 * @returns {{byteOrder:'II'|'MM', ifd0:Map, exif:Map, gps:Map}}
 */
function parseTiff(tiff) {
  let buf = tiff;
  if (buf.length >= 6 && buf.toString('latin1', 0, 6) === 'Exif\0\0') buf = buf.subarray(6);
  const r = new Reader(buf);
  const seen = new Set();
  const ifd0 = readIfd(r, r.u32(4), seen);
  const exifPtr = ifd0.get(TAGS.ExifIFD);
  const gpsPtr = ifd0.get(TAGS.GPSIFD);
  const exif = exifPtr ? readIfd(r, exifPtr.value[0], seen) : new Map();
  const gps = gpsPtr ? readIfd(r, gpsPtr.value[0], seen) : new Map();
  return { byteOrder: r.le ? 'II' : 'MM', ifd0, exif, gps };
}

// ---- helpers to convert raw entries to friendly values ----------------------

function num(entry, idx = 0) {
  if (!entry || !Array.isArray(entry.value) || entry.value.length <= idx) return null;
  const v = entry.value[idx];
  if (Array.isArray(v)) return v[1] === 0 ? null : v[0] / v[1];
  return typeof v === 'number' ? v : null;
}

function str(entry) {
  return entry && typeof entry.value === 'string' && entry.value.length ? entry.value : null;
}

function dmsToDecimal(entry, ref) {
  if (!entry || entry.value.length < 3) return null;
  const d = num(entry, 0), m = num(entry, 1), s = num(entry, 2);
  if (d === null || m === null || s === null) return null;
  let dec = d + m / 60 + s / 3600;
  if (ref === 'S' || ref === 'W') dec = -dec;
  return Math.round(dec * 1e7) / 1e7;
}

/** "2026:09:24 10:42:31" + "+05:30" -> "2026-09-24T10:42:31+05:30" */
function exifDateToIso(dt, offset, subsec) {
  if (!dt) return null;
  const m = /^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(dt);
  if (!m) return null;
  const frac = subsec && /^\d+$/.test(subsec) ? `.${subsec.padEnd(3, '0').slice(0, 3)}` : '';
  const off = offset && /^[+-]\d{2}:\d{2}$/.test(offset) ? offset : '';
  return `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${frac}${off}`;
}

const ORIENTATION_LABEL = {
  1: 'Normal (0°)',
  2: 'Mirrored horizontal',
  3: 'Rotated 180°',
  4: 'Mirrored vertical',
  5: 'Mirrored horizontal, rotated 270° CW',
  6: 'Rotated 90° CW',
  7: 'Mirrored horizontal, rotated 90° CW',
  8: 'Rotated 270° CW',
};

/** Convert parsed TIFF into the metadata shape returned by the API. */
function tiffToMetadata(parsed) {
  const { ifd0, exif, gps } = parsed;

  const latRef = str(gps.get(TAGS.GPSLatitudeRef));
  const lonRef = str(gps.get(TAGS.GPSLongitudeRef));
  const latitude = dmsToDecimal(gps.get(TAGS.GPSLatitude), latRef);
  const longitude = dmsToDecimal(gps.get(TAGS.GPSLongitude), lonRef);
  let altitude = num(gps.get(TAGS.GPSAltitude));
  const altRef = num(gps.get(TAGS.GPSAltitudeRef));
  if (altitude !== null && altRef === 1) altitude = -altitude;
  const accuracy = num(gps.get(TAGS.GPSHPositioningError));

  const resUnit = num(ifd0.get(TAGS.ResolutionUnit));
  const lensModel = str(exif.get(TAGS.LensModel));
  let facing = null;
  if (lensModel) {
    if (/front/i.test(lensModel)) facing = 'front';
    else if (/back|rear/i.test(lensModel)) facing = 'back';
  }

  const orientation = num(ifd0.get(TAGS.Orientation));

  return {
    exifByteOrder: parsed.byteOrder,
    gps: latitude !== null && longitude !== null
      ? {
        latitude,
        longitude,
        latitudeRef: latRef,
        longitudeRef: lonRef,
        altitude: altitude !== null ? Math.round(altitude * 100) / 100 : null,
        horizontalAccuracyM: accuracy !== null ? Math.round(accuracy * 100) / 100 : null,
        gpsDate: str(gps.get(TAGS.GPSDateStamp)),
      }
      : null,
    capture: {
      dateTimeOriginal: str(exif.get(TAGS.DateTimeOriginal)),
      dateTime: str(ifd0.get(TAGS.DateTime)),
      offsetTimeOriginal: str(exif.get(TAGS.OffsetTimeOriginal)),
      capturedAt: exifDateToIso(
        str(exif.get(TAGS.DateTimeOriginal)) || str(ifd0.get(TAGS.DateTime)),
        str(exif.get(TAGS.OffsetTimeOriginal)) || str(exif.get(TAGS.OffsetTime)),
        str(exif.get(TAGS.SubSecTimeOriginal)),
      ),
    },
    camera: {
      make: str(ifd0.get(TAGS.Make)),
      model: str(ifd0.get(TAGS.Model)),
      lensMake: str(exif.get(TAGS.LensMake)),
      lensModel,
      facing,
      software: str(ifd0.get(TAGS.Software)),
      exposureTime: num(exif.get(TAGS.ExposureTime)),
      fNumber: num(exif.get(TAGS.FNumber)),
      iso: num(exif.get(TAGS.ISO)),
      focalLengthMm: num(exif.get(TAGS.FocalLength)),
    },
    orientation: orientation !== null
      ? { value: orientation, label: ORIENTATION_LABEL[orientation] || 'Unknown' }
      : null,
    resolution: {
      xResolution: num(ifd0.get(TAGS.XResolution)),
      yResolution: num(ifd0.get(TAGS.YResolution)),
      resolutionUnit: resUnit === 2 ? 'inch' : resUnit === 3 ? 'cm' : resUnit === 1 ? 'none' : null,
      exifImageWidth: num(ifd0.get(TAGS.ImageWidth)) ?? num(exif.get(TAGS.PixelXDimension)),
      exifImageHeight: num(ifd0.get(TAGS.ImageLength)) ?? num(exif.get(TAGS.PixelYDimension)),
    },
  };
}

module.exports = { parseTiff, tiffToMetadata, TAGS, exifDateToIso, dmsToDecimal };
