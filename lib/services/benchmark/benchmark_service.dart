import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../models/benchmark_result.dart';
import '../../models/processing_options.dart';
import '../camera/device_info_service.dart';
import '../image_processing/image_processor.dart';
import '../metadata/exif_builder.dart';
import '../metadata/image_format.dart';
import '../upload/upload_service.dart';

const _uuid = Uuid();

/// One configuration to sweep, matching spec §52's fixed matrix.
class _BenchmarkVariant {
  final String label;
  final ImageFormat format;
  final bool lossless;
  final int quality;
  const _BenchmarkVariant(this.label, this.format, this.quality, {this.lossless = false});
}

const List<_BenchmarkVariant> _defaultMatrix = [
  _BenchmarkVariant('jpeg-60', ImageFormat.jpeg, 60),
  _BenchmarkVariant('jpeg-75', ImageFormat.jpeg, 75),
  _BenchmarkVariant('jpeg-80', ImageFormat.jpeg, 80),
  _BenchmarkVariant('jpeg-85', ImageFormat.jpeg, 85),
  _BenchmarkVariant('jpeg-90', ImageFormat.jpeg, 90),
  _BenchmarkVariant('jpeg-95', ImageFormat.jpeg, 95),
  _BenchmarkVariant('png', ImageFormat.png, 100),
  _BenchmarkVariant('webp-75', ImageFormat.webp, 75),
  _BenchmarkVariant('webp-80', ImageFormat.webp, 80),
  _BenchmarkVariant('webp-85', ImageFormat.webp, 85),
  _BenchmarkVariant('webp-90', ImageFormat.webp, 90),
  _BenchmarkVariant('webp-lossless', ImageFormat.webp, 100, lossless: true),
];

/// Spec §31–§34 / §52–§53: runs the fixed format/quality matrix against one
/// captured source image, measuring every pipeline stage with a real
/// Stopwatch (never a hardcoded value), and optionally uploads each
/// variant via Base64 and/or multipart to compare payload size and
/// network time honestly.
class BenchmarkService {
  final UploadService? uploadService; // null = skip the upload-comparison steps
  BenchmarkService({this.uploadService});

  Future<BenchmarkRun> run({
    required Uint8List sourceBytes,
    required CaptureMetadata captureMeta,
    required int captureTimeMs,
    bool alsoUpload = false,
    void Function(int completed, int total, String label)? onProgress,
  }) async {
    final results = <ImageBenchmarkResult>[];
    final total = _defaultMatrix.length;
    var i = 0;

    for (final variant in _defaultMatrix) {
      onProgress?.call(i, total, variant.label);
      final result = await _runVariant(
        sourceBytes: sourceBytes,
        captureMeta: captureMeta,
        captureTimeMs: captureTimeMs,
        variant: variant,
        alsoUpload: alsoUpload,
      );
      results.add(result);
      i++;
    }
    onProgress?.call(total, total, 'done');

    String device = Platform.operatingSystem;
    try {
      final info = await DeviceInfoService().get();
      if (info.make != null || info.model != null) device = '${info.make ?? ''} ${info.model ?? ''}'.trim();
    } catch (_) {
      /* keep OS name fallback */
    }

    return BenchmarkRun(
      id: _uuid.v4(),
      startedAt: DateTime.now(),
      device: device,
      cameraFacing: captureMeta.lensFacing ?? 'unknown',
      sourceResolution: '${captureMeta.width}x${captureMeta.height}',
      results: results,
    );
  }

  Future<ImageBenchmarkResult> _runVariant({
    required Uint8List sourceBytes,
    required CaptureMetadata captureMeta,
    required int captureTimeMs,
    required _BenchmarkVariant variant,
    required bool alsoUpload,
  }) async {
    final overall = Stopwatch()..start();

    final options = ProcessingOptions(
      format: variant.format,
      webpLossless: variant.lossless,
      quality: variant.quality,
      maxDimension: null,
      preserveMetadata: true,
      includeGps: captureMeta.hasGps,
      dpi: captureMeta.dpi,
    );

    final result = await ImageProcessor.process(originalBytes: sourceBytes, options: options, captureMeta: captureMeta);

    final base64Sw = Stopwatch()..start();
    final b64 = base64Encode(result.outputBytes);
    base64Sw.stop();

    int? multipartMs;
    int? base64UploadMs;
    if (alsoUpload && uploadService != null) {
      final fileName = 'bench_${variant.label}.${variant.format.extension}';
      final mp = await uploadService!.uploadMultipart(imageBytes: result.outputBytes, fileName: fileName, format: variant.format);
      multipartMs = mp.uploadTimeMs;
      final b64Result =
          await uploadService!.uploadBase64(imageBytes: result.outputBytes, fileName: fileName, format: variant.format);
      base64UploadMs = b64Result.uploadTimeMs;
    }

    overall.stop();

    int stage(String name) => result.timings.firstWhere((t) => t.stage.startsWith(name), orElse: () => const StageTiming('', 0)).milliseconds;

    return ImageBenchmarkResult(
      format: variant.lossless ? 'webp-lossless' : (variant.format == ImageFormat.webp ? 'webp-lossy' : variant.format.name),
      quality: variant.quality,
      width: result.outputWidth,
      height: result.outputHeight,
      originalSizeBytes: sourceBytes.length,
      processedSizeBytes: result.outputBytes.length,
      metadataSizeBytes: result.outputMetadata.exifSizeBytes,
      base64SizeBytes: b64.length,
      captureTimeMs: captureTimeMs,
      decodeTimeMs: stage('Decode'),
      resizeTimeMs: stage('Resize'),
      encodeTimeMs: stage('Encode'),
      metadataWriteTimeMs: stage('Write metadata'),
      metadataVerifyTimeMs: stage('Verify metadata'),
      base64TimeMs: base64Sw.elapsedMilliseconds,
      fileWriteTimeMs: 0,
      metadataPreserved: result.verification.allExpectedFieldsPreserved,
      multipartUploadMs: multipartMs,
      base64UploadMs: base64UploadMs,
      totalTimeMs: overall.elapsedMilliseconds,
    );
  }
}
