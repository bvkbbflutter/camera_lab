import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/benchmark_result.dart';

/// Spec §53: export a benchmark run as CSV or JSON and hand it to the
/// system share sheet.
class BenchmarkExport {
  static Future<File> _writeTemp(String fileName, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  static Future<File> toJsonFile(BenchmarkRun run) async {
    final content = const JsonEncoder.withIndent('  ').convert(run.toJson());
    return _writeTemp('camera_lab_benchmark_${run.id}.json', content);
  }

  static Future<File> toCsvFile(BenchmarkRun run) async {
    final rows = <List<dynamic>>[
      [
        'format',
        'quality',
        'width',
        'height',
        'originalSizeBytes',
        'processedSizeBytes',
        'reductionPercent',
        'metadataSizeBytes',
        'base64SizeBytes',
        'decodeTimeMs',
        'resizeTimeMs',
        'encodeTimeMs',
        'metadataWriteTimeMs',
        'metadataVerifyTimeMs',
        'base64TimeMs',
        'metadataPreserved',
        'multipartUploadMs',
        'base64UploadMs',
        'totalTimeMs',
      ],
      for (final r in run.results)
        [
          r.format,
          r.quality,
          r.width,
          r.height,
          r.originalSizeBytes,
          r.processedSizeBytes,
          r.reductionPercent.toStringAsFixed(1),
          r.metadataSizeBytes,
          r.base64SizeBytes,
          r.decodeTimeMs,
          r.resizeTimeMs,
          r.encodeTimeMs,
          r.metadataWriteTimeMs,
          r.metadataVerifyTimeMs,
          r.base64TimeMs,
          r.metadataPreserved,
          r.multipartUploadMs ?? '',
          r.base64UploadMs ?? '',
          r.totalTimeMs,
        ],
    ];
    final csv = const ListToCsvConverter().convert(rows);
    return _writeTemp('camera_lab_benchmark_${run.id}.csv', csv);
  }

  static Future<void> shareJson(BenchmarkRun run) async {
    final file = await toJsonFile(run);
    await Share.shareXFiles([XFile(file.path)],
        text: 'Camera Lab benchmark results (JSON)');
  }

  static Future<void> shareCsv(BenchmarkRun run) async {
    final file = await toCsvFile(run);
    await Share.shareXFiles([XFile(file.path)],
        text: 'Camera Lab benchmark results (CSV)');
  }
}
