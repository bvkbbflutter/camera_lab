import 'dart:typed_data';

import 'crc32.dart';

const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

class PngInfo {
  final int width;
  final int height;
  final Uint8List? exif; // eXIf chunk payload, or null
  final int metadataBytes;
  final ({int xPpu, int yPpu, bool isMeters})? phys;

  const PngInfo({required this.width, required this.height, required this.exif, required this.metadataBytes, this.phys});
}

/// PNG is a chunked, lossless container. Metadata lives in standalone
/// ancillary chunks (eXIf for EXIF, pHYs for pixel density) rather than
/// JPEG-style markers, and each chunk carries its own CRC-32 — this class
/// computes valid CRCs so downstream readers don't reject the file.
///
/// Per requirement #13: PNG's metadata behavior is NOT assumed to mirror
/// JPEG's; this is a separate, purpose-built implementation.
class PngContainer {
  static PngInfo read(Uint8List buf) {
    _checkSignature(buf);
    var o = 8;
    int? width, height;
    Uint8List? exif;
    var metadataBytes = 0;
    ({int xPpu, int yPpu, bool isMeters})? phys;

    while (o + 12 <= buf.length) {
      final len = _u32be(buf, o);
      final type = String.fromCharCodes(buf.sublist(o + 4, o + 8));
      if (o + 12 + len > buf.length) throw const FormatException('PNG: truncated chunk');
      final data = buf.sublist(o + 8, o + 8 + len);
      if (type == 'IHDR') {
        width = _u32be(data, 0);
        height = _u32be(data, 4);
      } else if (type == 'eXIf') {
        exif ??= data;
        metadataBytes += 12 + len;
      } else if (type == 'pHYs' && len == 9) {
        phys = (xPpu: _u32be(data, 0), yPpu: _u32be(data, 4), isMeters: data[8] == 1);
        metadataBytes += 12 + len;
      } else if (type == 'tEXt' || type == 'iTXt' || type == 'zTXt' || type == 'iCCP') {
        metadataBytes += 12 + len;
      } else if (type == 'IEND') {
        break;
      }
      o += 12 + len;
    }
    if (width == null || height == null) throw const FormatException('PNG: missing IHDR');
    return PngInfo(width: width, height: height, exif: exif, metadataBytes: metadataBytes, phys: phys);
  }

  /// Removes any existing eXIf/pHYs chunks and inserts fresh ones right
  /// after IHDR (before IDAT), which is the conventional, broadly-supported
  /// position for ancillary chunks.
  static Uint8List embed(Uint8List original, {Uint8List? exifBytes, int? dpi}) {
    _checkSignature(original);
    final out = BytesBuilder();
    out.add(_pngSignature);

    var o = 8;
    var insertedAfterIhdr = false;
    while (o + 12 <= original.length) {
      final len = _u32be(original, o);
      final type = String.fromCharCodes(original.sublist(o + 4, o + 8));
      final chunkEnd = o + 12 + len;
      final isDroppedMeta = type == 'eXIf' || type == 'pHYs';

      if (!isDroppedMeta) {
        out.add(original.sublist(o, chunkEnd));
      }
      if (type == 'IHDR' && !insertedAfterIhdr) {
        insertedAfterIhdr = true;
        if (dpi != null) out.add(_buildPhysChunk(dpi));
        if (exifBytes != null) out.add(_buildChunk('eXIf', exifBytes));
      }
      o = chunkEnd;
      if (type == 'IEND') break;
    }
    return out.toBytes();
  }

  static void _checkSignature(Uint8List buf) {
    if (buf.length < 8) throw const FormatException('PNG: file too short');
    for (var i = 0; i < 8; i++) {
      if (buf[i] != _pngSignature[i]) throw const FormatException('PNG: bad signature');
    }
  }

  static Uint8List _buildPhysChunk(int dpi) {
    // pHYs stores pixels-per-meter, unit=1 (meter). 1 inch = 0.0254 m.
    final ppu = (dpi / 0.0254).round();
    final data = Uint8List(9);
    final bd = ByteData.sublistView(data);
    bd.setUint32(0, ppu, Endian.big);
    bd.setUint32(4, ppu, Endian.big);
    data[8] = 1; // meters
    return _buildChunk('pHYs', data);
  }

  static Uint8List _buildChunk(String type, Uint8List data) {
    final out = Uint8List(12 + data.length);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, data.length, Endian.big);
    out.setRange(4, 8, type.codeUnits);
    out.setRange(8, 8 + data.length, data);
    final crc = Crc32.compute(out, 4, 8 + data.length);
    bd.setUint32(8 + data.length, crc, Endian.big);
    return out;
  }

  static int _u32be(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}
