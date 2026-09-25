import 'dart:convert';
import 'dart:typed_data';

import 'exif_tags.dart';

/// A single rational number as stored by TIFF/EXIF (numerator/denominator).
class Rational {
  final int numerator;
  final int denominator;
  const Rational(this.numerator, this.denominator);

  double toDouble() => denominator == 0 ? 0 : numerator / denominator;

  /// Builds a rational approximating [value] with the given [denominator]
  /// (e.g. 100 for two decimal places of precision), which is how this
  /// module encodes exposure time, F-number, focal length, altitude, etc.
  factory Rational.fromDouble(double value, {int denominator = 1000}) {
    return Rational((value * denominator).round(), denominator);
  }
}

/// One decoded (or to-be-encoded) TIFF/EXIF directory entry.
class IfdEntry {
  final int tag;
  final int type;
  final int count;

  /// Decoded value: String (ascii), List<int> (byte/short/long),
  /// or List<Rational> (rational/srational).
  final Object value;

  const IfdEntry(this.tag, this.type, this.count, this.value);

  int? get asInt {
    if (value is List<int> && (value as List<int>).isNotEmpty) return (value as List<int>).first;
    if (value is List<Rational> && (value as List<Rational>).isNotEmpty) {
      return (value as List<Rational>).first.toDouble().round();
    }
    return null;
  }

  double? get asDouble {
    if (value is List<Rational> && (value as List<Rational>).isNotEmpty) {
      return (value as List<Rational>).first.toDouble();
    }
    if (value is List<int> && (value as List<int>).isNotEmpty) {
      return (value as List<int>).first.toDouble();
    }
    return null;
  }

  String? get asString => value is String ? value as String : null;

  List<Rational>? get asRationalList => value is List<Rational> ? value as List<Rational> : null;
}

/// Parsed TIFF/EXIF block: IFD0 plus the Exif and GPS sub-IFDs.
class TiffData {
  final bool littleEndian;
  final Map<int, IfdEntry> ifd0;
  final Map<int, IfdEntry> exif;
  final Map<int, IfdEntry> gps;

  const TiffData({
    required this.littleEndian,
    required this.ifd0,
    required this.exif,
    required this.gps,
  });

  bool get isEmpty => ifd0.isEmpty && exif.isEmpty && gps.isEmpty;
}

/// Reads a raw TIFF block (the bytes after "Exif\0\0" in a JPEG APP1
/// segment, or the raw contents of a PNG eXIf / WebP EXIF chunk).
class TiffReader {
  static TiffData parse(Uint8List bytes) {
    var buf = bytes;
    if (buf.length >= 6 && ascii.decode(buf.sublist(0, 6), allowInvalid: true) == 'Exif\u0000\u0000') {
      buf = buf.sublist(6);
    }
    if (buf.length < 8) {
      throw const FormatException('TIFF block too short');
    }
    final marker = ascii.decode(buf.sublist(0, 2));
    final bool le;
    if (marker == 'II') {
      le = true;
    } else if (marker == 'MM') {
      le = false;
    } else {
      throw FormatException('Not a TIFF block (bad byte order "$marker")');
    }
    final bd = ByteData.sublistView(buf);
    final magic = _u16(bd, 2, le);
    if (magic != 42) throw const FormatException('Not a TIFF block (bad magic)');

    final ifd0Offset = _u32(bd, 4, le);
    final seen = <int>{};
    final ifd0 = _readIfd(buf, bd, ifd0Offset, le, seen);
    final exifPtr = ifd0[ExifTag.exifIfdPointer]?.asInt;
    final gpsPtr = ifd0[ExifTag.gpsIfdPointer]?.asInt;
    final exif = exifPtr != null ? _readIfd(buf, bd, exifPtr, le, seen) : <int, IfdEntry>{};
    final gps = gpsPtr != null ? _readIfd(buf, bd, gpsPtr, le, seen) : <int, IfdEntry>{};

    return TiffData(littleEndian: le, ifd0: ifd0, exif: exif, gps: gps);
  }

  static Map<int, IfdEntry> _readIfd(Uint8List buf, ByteData bd, int offset, bool le, Set<int> seen) {
    final out = <int, IfdEntry>{};
    if (offset <= 0 || offset + 2 > buf.length || seen.contains(offset)) return out;
    seen.add(offset);
    final count = _u16(bd, offset, le);
    for (var i = 0; i < count; i++) {
      final entryOffset = offset + 2 + i * 12;
      if (entryOffset + 12 > buf.length) break;
      final tag = _u16(bd, entryOffset, le);
      final type = _u16(bd, entryOffset + 2, le);
      final valueCount = _u32(bd, entryOffset + 4, le);
      final typeSize = TiffType.sizeOf(type);
      final totalSize = typeSize * valueCount;
      if (totalSize <= 0) continue;
      final valueOffset = totalSize <= 4 ? entryOffset + 8 : _u32(bd, entryOffset + 8, le);
      if (valueOffset < 0 || valueOffset + totalSize > buf.length) continue; // corrupt, skip
      final entry = _decodeValue(buf, bd, type, valueCount, valueOffset, le, tag);
      if (entry != null) out[tag] = entry;
    }
    return out;
  }

  static IfdEntry? _decodeValue(Uint8List buf, ByteData bd, int type, int count, int offset, bool le, int tag) {
    switch (type) {
      case TiffType.ascii:
        final raw = buf.sublist(offset, offset + count);
        final nul = raw.indexOf(0);
        final str = latin1.decode(nul == -1 ? raw : raw.sublist(0, nul));
        return IfdEntry(tag, type, count, str.trim());
      case TiffType.byte:
      case TiffType.undefined:
        return IfdEntry(tag, type, count, buf.sublist(offset, offset + count).toList());
      case TiffType.short:
        return IfdEntry(tag, type, count, [for (var i = 0; i < count; i++) _u16(bd, offset + i * 2, le)]);
      case TiffType.long:
        return IfdEntry(tag, type, count, [for (var i = 0; i < count; i++) _u32(bd, offset + i * 4, le)]);
      case TiffType.slong:
        return IfdEntry(tag, type, count, [for (var i = 0; i < count; i++) _i32(bd, offset + i * 4, le)]);
      case TiffType.rational:
        return IfdEntry(tag, type, count, [
          for (var i = 0; i < count; i++)
            Rational(_u32(bd, offset + i * 8, le), _u32(bd, offset + i * 8 + 4, le)),
        ]);
      case TiffType.srational:
        return IfdEntry(tag, type, count, [
          for (var i = 0; i < count; i++)
            Rational(_i32(bd, offset + i * 8, le), _i32(bd, offset + i * 8 + 4, le)),
        ]);
      default:
        return null;
    }
  }

  static int _u16(ByteData bd, int o, bool le) => le ? bd.getUint16(o, Endian.little) : bd.getUint16(o, Endian.big);
  static int _u32(ByteData bd, int o, bool le) => le ? bd.getUint32(o, Endian.little) : bd.getUint32(o, Endian.big);
  static int _i32(ByteData bd, int o, bool le) => le ? bd.getInt32(o, Endian.little) : bd.getInt32(o, Endian.big);
}

/// Builds a valid little-endian TIFF/EXIF block from scratch: IFD0 with an
/// optional Exif sub-IFD and GPS sub-IFD, correctly linked via pointer tags,
/// with values >4 bytes placed in the overflow ("value") area as TIFF
/// requires. This is the single mechanism this app uses to embed GPS,
/// date/time, camera and resolution metadata into JPEG/PNG/WebP files —
/// there is no separate JSON metadata sidecar.
class TiffWriter {
  final Map<int, IfdEntry> ifd0;
  final Map<int, IfdEntry> exif;
  final Map<int, IfdEntry> gps;

  TiffWriter({Map<int, IfdEntry>? ifd0, Map<int, IfdEntry>? exif, Map<int, IfdEntry>? gps})
      : ifd0 = ifd0 ?? {},
        exif = exif ?? {},
        gps = gps ?? {};

  Uint8List build() {
    final ifd0Entries = Map<int, IfdEntry>.from(ifd0);
    if (exif.isNotEmpty) {
      ifd0Entries[ExifTag.exifIfdPointer] = const IfdEntry(ExifTag.exifIfdPointer, TiffType.long, 1, [0]);
    }
    if (gps.isNotEmpty) {
      ifd0Entries[ExifTag.gpsIfdPointer] = const IfdEntry(ExifTag.gpsIfdPointer, TiffType.long, 1, [0]);
    }

    final ifd0Sorted = ifd0Entries.keys.toList()..sort();
    final exifSorted = exif.keys.toList()..sort();
    final gpsSorted = gps.keys.toList()..sort();

    const headerSize = 8;
    final ifd0Size = 2 + 12 * ifd0Sorted.length + 4;
    final exifSize = exif.isEmpty ? 0 : 2 + 12 * exifSorted.length + 4;
    final gpsSize = gps.isEmpty ? 0 : 2 + 12 * gpsSorted.length + 4;

    final ifd0Offset = headerSize;
    final exifOffset = ifd0Offset + ifd0Size;
    final gpsOffset = exifOffset + exifSize;
    var overflowCursor = gpsOffset + gpsSize;

    // Pre-encode every entry's raw value bytes and decide inline vs overflow.
    final ifd0Bytes = <int, Uint8List>{};
    final exifBytes = <int, Uint8List>{};
    final gpsBytes = <int, Uint8List>{};
    for (final tag in ifd0Sorted) {
      ifd0Bytes[tag] = _encodeValue(ifd0Entries[tag]!);
    }
    for (final tag in exifSorted) {
      exifBytes[tag] = _encodeValue(exif[tag]!);
    }
    for (final tag in gpsSorted) {
      gpsBytes[tag] = _encodeValue(gps[tag]!);
    }

    final overflowOffsets = <int, int>{}; // composite key: ifd*100000+tag -> offset
    void planOverflow(List<int> tags, Map<int, Uint8List> bytesMap, int ifdId) {
      for (final tag in tags) {
        final len = bytesMap[tag]!.length;
        if (len > 4) {
          overflowOffsets[ifdId * 1000000 + tag] = overflowCursor;
          overflowCursor += len;
        }
      }
    }

    planOverflow(ifd0Sorted, ifd0Bytes, 0);
    planOverflow(exifSorted, exifBytes, 1);
    planOverflow(gpsSorted, gpsBytes, 2);

    final total = overflowCursor;
    final out = Uint8List(total);
    final bd = ByteData.sublistView(out);

    // Header: "II", 42, offset to IFD0
    out[0] = 0x49;
    out[1] = 0x49;
    bd.setUint16(2, 42, Endian.little);
    bd.setUint32(4, ifd0Offset, Endian.little);

    void writeIfd(int baseOffset, List<int> tags, Map<int, IfdEntry> entries, Map<int, Uint8List> bytesMap, int ifdId) {
      bd.setUint16(baseOffset, tags.length, Endian.little);
      var entryPos = baseOffset + 2;
      for (final tag in tags) {
        final entry = entries[tag]!;
        final valueBytes = bytesMap[tag]!;
        bd.setUint16(entryPos, tag, Endian.little);
        bd.setUint16(entryPos + 2, entry.type, Endian.little);
        bd.setUint32(entryPos + 4, entry.count, Endian.little);

        int? patchedOffset;
        if (tag == ExifTag.exifIfdPointer) {
          patchedOffset = exifOffset;
        } else if (tag == ExifTag.gpsIfdPointer) {
          patchedOffset = gpsOffset;
        }

        if (patchedOffset != null) {
          bd.setUint32(entryPos + 8, patchedOffset, Endian.little);
        } else if (valueBytes.length <= 4) {
          out.setRange(entryPos + 8, entryPos + 8 + valueBytes.length, valueBytes);
          for (var p = valueBytes.length; p < 4; p++) {
            out[entryPos + 8 + p] = 0;
          }
        } else {
          final off = overflowOffsets[ifdId * 1000000 + tag]!;
          bd.setUint32(entryPos + 8, off, Endian.little);
          out.setRange(off, off + valueBytes.length, valueBytes);
        }
        entryPos += 12;
      }
      bd.setUint32(entryPos, 0, Endian.little); // next-IFD offset: none
    }

    writeIfd(ifd0Offset, ifd0Sorted, ifd0Entries, ifd0Bytes, 0);
    if (exif.isNotEmpty) writeIfd(exifOffset, exifSorted, exif, exifBytes, 1);
    if (gps.isNotEmpty) writeIfd(gpsOffset, gpsSorted, gps, gpsBytes, 2);

    return out;
  }

  static Uint8List _encodeValue(IfdEntry entry) {
    switch (entry.type) {
      case TiffType.ascii:
        final str = entry.asString ?? '';
        final bytes = latin1.encode(str);
        final withNul = Uint8List(bytes.length + 1)..setRange(0, bytes.length, bytes);
        return withNul;
      case TiffType.byte:
      case TiffType.undefined:
        final list = (entry.value as List<int>);
        return Uint8List.fromList(list);
      case TiffType.short:
        final list = (entry.value as List<int>);
        final out = Uint8List(list.length * 2);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < list.length; i++) {
          bd.setUint16(i * 2, list[i], Endian.little);
        }
        return out;
      case TiffType.long:
        final list = (entry.value as List<int>);
        final out = Uint8List(list.length * 4);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < list.length; i++) {
          bd.setUint32(i * 4, list[i], Endian.little);
        }
        return out;
      case TiffType.slong:
        final list = (entry.value as List<int>);
        final out = Uint8List(list.length * 4);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < list.length; i++) {
          bd.setInt32(i * 4, list[i], Endian.little);
        }
        return out;
      case TiffType.rational:
      case TiffType.srational:
        final list = (entry.value as List<Rational>);
        final out = Uint8List(list.length * 8);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < list.length; i++) {
          bd.setUint32(i * 8, list[i].numerator, Endian.little);
          bd.setUint32(i * 8 + 4, list[i].denominator, Endian.little);
        }
        return out;
      default:
        return Uint8List(0);
    }
  }
}
