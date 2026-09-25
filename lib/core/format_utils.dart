import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String formatDate(DateTime dt) => DateFormat('d MMMM yyyy').format(dt);

String formatTime(DateTime dt) => DateFormat('HH:mm:ss').format(dt);

String formatPercent(double p) => '${p.toStringAsFixed(1)}%';

String formatMs(int ms) => ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)} s' : '$ms ms';
