import 'dart:convert';
import 'dart:typed_data';

const List<int> _sofMarkers = [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf];

/// Result of reading a JPEG's segment structure.
class JpegInfo {
  final int width;
  final int height;
  final Uint8List? exif; // raw TIFF bytes (after "Exif\0\0"), or null
  final bool progressive;
  final int metadataBytes;

  const JpegInfo({
    required this.width,
    required this.height,
    required this.exif,
    required this.progressive,
    required this.metadataBytes,
  });
}

/// Reads and writes the EXIF (APP1) segment of a JPEG file without touching
/// the compressed scan data, so re-embedding metadata never re-encodes
/// pixels. Requirement: "Do not assume decoding and re-encoding
/// automatically preserves EXIF — explicitly read and write it."
class JpegContainer {
  static JpegInfo read(Uint8List buf) {
    if (buf.length < 4 || buf[0] != 0xFF || buf[1] != 0xD8) {
      throw const FormatException('Not a JPEG file (missing SOI marker)');
    }
    var o = 2;
    int? width, height;
    Uint8List? exif;
    var progressive = false;
    var metadataBytes = 0;

    while (o + 4 <= buf.length) {
      if (buf[o] != 0xFF) throw FormatException('JPEG: expected marker at offset $o');
      var marker = buf[o + 1];
      while (marker == 0xFF && o + 2 < buf.length) {
        o++;
        marker = buf[o + 1];
      }
      o += 2;
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
      if (marker == 0xD9) break; // EOI
      final len = (buf[o] << 8) | buf[o + 1];
      if (len < 2 || o + len > buf.length) throw const FormatException('JPEG: truncated segment');
      final data = buf.sublist(o + 2, o + len);

      if (marker == 0xE1 && data.length >= 6 && ascii.decode(data.sublist(0, 6), allowInvalid: true) == 'Exif\u0000\u0000') {
        exif ??= data.sublist(6);
        metadataBytes += len + 2;
      } else if (marker == 0xE1 || marker == 0xED || marker == 0xE2) {
        metadataBytes += len + 2;
      } else if (_sofMarkers.contains(marker) && data.length >= 5) {
        height = (data[1] << 8) | data[2];
        width = (data[3] << 8) | data[4];
        progressive = marker == 0xC2 || marker == 0xC6 || marker == 0xCA || marker == 0xCE;
      }
      if (marker == 0xDA) break; // SOS
      o += len;
    }

    if (width == null || height == null) {
      throw const FormatException('JPEG: no SOF marker found (not decodable)');
    }
    return JpegInfo(width: width, height: height, exif: exif, progressive: progressive, metadataBytes: metadataBytes);
  }

  /// Removes any existing APP1 EXIF segment and inserts [tiffBytes] as a
  /// fresh one immediately after SOI. Leaves every other byte (including
  /// all compressed image data) untouched.
  static Uint8List embed(Uint8List original, Uint8List tiffBytes) {
    if (original.length < 4 || original[0] != 0xFF || original[1] != 0xD8) {
      throw const FormatException('Not a JPEG file (missing SOI marker)');
    }
    final out = BytesBuilder();
    out.add([0xFF, 0xD8]); // SOI
    final exifHeader = Uint8List.fromList([...ascii.encode('Exif'), 0, 0]);
    final segLen = exifHeader.length + tiffBytes.length + 2;
    if (segLen > 0xFFFF) {
      throw const FormatException('EXIF payload too large for a single APP1 segment');
    }
    out.add([0xFF, 0xE1, (segLen >> 8) & 0xFF, segLen & 0xFF]);
    out.add(exifHeader);
    out.add(tiffBytes);

    var o = 2;
    while (o + 4 <= original.length) {
      if (original[o] != 0xFF) break;
      var marker = original[o + 1];
      while (marker == 0xFF && o + 2 < original.length) {
        o++;
        marker = original[o + 1];
      }
      final markerStart = o;
      o += 2;
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (marker == 0xD9) {
        out.add(original.sublist(markerStart));
        break;
      }
      final len = (original[o] << 8) | original[o + 1];
      final data = original.sublist(o + 2, o + len);
      final isOldExif =
          marker == 0xE1 && data.length >= 6 && ascii.decode(data.sublist(0, 6), allowInvalid: true) == 'Exif\u0000\u0000';
      if (!isOldExif) {
        out.add(original.sublist(markerStart, o + len));
      }
      if (marker == 0xDA) {
        // Start of scan: copy everything remaining verbatim (entropy-coded data).
        out.add(original.sublist(o + len));
        break;
      }
      o += len;
    }
    return out.toBytes();
  }
}
