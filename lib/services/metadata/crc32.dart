import 'dart:typed_data';

/// Standard CRC-32 (as used by PNG chunk trailers and the zlib format).
class Crc32 {
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  static int compute(Uint8List bytes, [int start = 0, int? end]) {
    var crc = 0xFFFFFFFF;
    final e = end ?? bytes.length;
    for (var i = start; i < e; i++) {
      crc = _table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
