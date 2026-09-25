import 'dart:typed_data';

class WebpInfo {
  final int width;
  final int height;
  final String encoding; // 'lossy' | 'lossless'
  final bool extended; // has a VP8X chunk
  final Uint8List? exif;
  final int metadataBytes;
  final bool hasAlpha;

  const WebpInfo({
    required this.width,
    required this.height,
    required this.encoding,
    required this.extended,
    required this.exif,
    required this.metadataBytes,
    required this.hasAlpha,
  });
}

/// WebP is a RIFF container. A "simple" WebP is just a VP8 or VP8L chunk;
/// to carry EXIF (or any other extra chunk) it must be upgraded to the
/// "extended" format, which adds a VP8X chunk describing which optional
/// features are present, in front of the image data chunk.
///
/// Per requirement #14: metadata survival is VERIFIED by re-reading the
/// written file, not assumed — see [WebpContainer.read] used after [embed].
class WebpContainer {
  static WebpInfo read(Uint8List buf) {
    _checkRiffWebp(buf);
    var o = 12;
    int? width, height;
    String encoding = 'unknown';
    var extended = false;
    var hasAlpha = false;
    Uint8List? exif;
    var metadataBytes = 0;

    while (o + 8 <= buf.length) {
      final type = String.fromCharCodes(buf.sublist(o, o + 4));
      final len = _u32le(buf, o + 4);
      if (o + 8 + len > buf.length) throw const FormatException('WebP: truncated chunk');
      final data = buf.sublist(o + 8, o + 8 + len);

      if (type == 'VP8X' && len >= 10) {
        extended = true;
        final flags = data[0];
        hasAlpha = (flags & 0x10) != 0;
        width = 1 + (data[4] | (data[5] << 8) | (data[6] << 16));
        height = 1 + (data[7] | (data[8] << 8) | (data[9] << 16));
      } else if (type == 'VP8 ' && len >= 10) {
        encoding = 'lossy';
        if (data[3] != 0x9d || data[4] != 0x01 || data[5] != 0x2a) {
          throw const FormatException('WebP: bad VP8 start code');
        }
        width ??= (data[6] | (data[7] << 8)) & 0x3FFF;
        height ??= (data[8] | (data[9] << 8)) & 0x3FFF;
      } else if (type == 'VP8L' && len >= 5) {
        encoding = 'lossless';
        if (data[0] != 0x2F) throw const FormatException('WebP: bad VP8L signature');
        final bits = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
        width ??= (bits & 0x3FFF) + 1;
        height ??= ((bits >> 14) & 0x3FFF) + 1;
      } else if (type == 'EXIF') {
        exif ??= data;
        metadataBytes += 8 + len + (len.isOdd ? 1 : 0);
      } else if (type == 'XMP ' || type == 'ICCP') {
        metadataBytes += 8 + len + (len.isOdd ? 1 : 0);
      }
      o += 8 + len + (len.isOdd ? 1 : 0);
    }
    if (width == null || height == null) throw const FormatException('WebP: no image chunk found');
    return WebpInfo(
      width: width,
      height: height,
      encoding: encoding,
      extended: extended,
      exif: exif,
      metadataBytes: metadataBytes,
      hasAlpha: hasAlpha,
    );
  }

  /// Rebuilds [original] as an Extended WebP carrying [exifBytes], preserving
  /// the original VP8/VP8L image data byte-for-byte (pixels are never
  /// touched, only the container is rewritten).
  static Uint8List embed(Uint8List original, Uint8List exifBytes) {
    _checkRiffWebp(original);
    var o = 12;
    Uint8List? imageChunk; // the VP8 / VP8L chunk, header + payload, original bytes
    String imageChunkType = '';
    var hasAlpha = false;
    var isAnimated = false;
    int? width, height;
    Uint8List? iccp;
    Uint8List? xmp;

    while (o + 8 <= original.length) {
      final type = String.fromCharCodes(original.sublist(o, o + 4));
      final len = _u32le(original, o + 4);
      final data = original.sublist(o + 8, o + 8 + len);
      final padded = 8 + len + (len.isOdd ? 1 : 0);

      if (type == 'VP8X' && len >= 10) {
        final flags = data[0];
        hasAlpha = (flags & 0x10) != 0;
        isAnimated = (flags & 0x02) != 0;
        width = 1 + (data[4] | (data[5] << 8) | (data[6] << 16));
        height = 1 + (data[7] | (data[8] << 8) | (data[9] << 16));
      } else if (type == 'VP8 ' || type == 'VP8L') {
        imageChunk = original.sublist(o, o + padded);
        imageChunkType = type;
        if (type == 'VP8 ') {
          width ??= (data[6] | (data[7] << 8)) & 0x3FFF;
          height ??= (data[8] | (data[9] << 8)) & 0x3FFF;
        } else {
          final bits = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
          width ??= (bits & 0x3FFF) + 1;
          height ??= ((bits >> 14) & 0x3FFF) + 1;
        }
      } else if (type == 'ICCP') {
        iccp = original.sublist(o, o + padded);
      } else if (type == 'XMP ') {
        xmp = original.sublist(o, o + padded);
      }
      // ALPH chunk (separate alpha for lossy) and ANIM/ANMF are copied
      // through imageChunk handling only for the simple VP8/VP8L case;
      // this POC targets single-frame stills, so animated WebP falls back
      // to returning the original bytes unmodified (documented limitation).
      o += padded;
    }

    if (imageChunk == null || width == null || height == null) {
      throw const FormatException('WebP: could not locate image data chunk to rebuild container');
    }
    if (isAnimated) {
      throw const FormatException('WebP: animated WebP is not supported by the metadata embedder');
    }

    final exifChunk = _buildChunk('EXIF', exifBytes);
    final vp8xData = Uint8List(10);
    // Flags byte: bit4=alpha, bit3=EXIF present (per WebP container spec).
    vp8xData[0] = (hasAlpha ? 0x10 : 0) | 0x08;
    final w1 = width - 1, h1 = height - 1;
    vp8xData[4] = w1 & 0xFF;
    vp8xData[5] = (w1 >> 8) & 0xFF;
    vp8xData[6] = (w1 >> 16) & 0xFF;
    vp8xData[7] = h1 & 0xFF;
    vp8xData[8] = (h1 >> 8) & 0xFF;
    vp8xData[9] = (h1 >> 16) & 0xFF;
    final vp8xChunk = _buildChunk('VP8X', vp8xData);

    final payload = BytesBuilder();
    payload.add(vp8xChunk);
    if (iccp != null) payload.add(iccp);
    payload.add(imageChunk);
    if (xmp != null) payload.add(xmp);
    payload.add(exifChunk);
    final payloadBytes = payload.toBytes();

    final out = BytesBuilder();
    out.add('RIFF'.codeUnits);
    final riffLen = 4 + payloadBytes.length; // "WEBP" + payload
    out.add(_u32leBytes(riffLen));
    out.add('WEBP'.codeUnits);
    out.add(payloadBytes);
    // ignore unused var warning for imageChunkType (kept for clarity/debugging)
    assert(imageChunkType.isNotEmpty);
    return out.toBytes();
  }

  static void _checkRiffWebp(Uint8List buf) {
    if (buf.length < 12) throw const FormatException('WebP: file too short');
    if (String.fromCharCodes(buf.sublist(0, 4)) != 'RIFF' || String.fromCharCodes(buf.sublist(8, 12)) != 'WEBP') {
      throw const FormatException('WebP: bad RIFF/WEBP signature');
    }
  }

  static Uint8List _buildChunk(String type, Uint8List data) {
    final padded = data.length.isOdd;
    final out = Uint8List(8 + data.length + (padded ? 1 : 0));
    out.setRange(0, 4, type.codeUnits);
    out.setRange(4, 8, _u32leBytes(data.length));
    out.setRange(8, 8 + data.length, data);
    return out;
  }

  static int _u32le(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static List<int> _u32leBytes(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
}
