/// Spec §32: one row of a benchmark run. Every field is a real measurement
/// — nothing here is a hardcoded/estimated value.
class ImageBenchmarkResult {
  final String format; // 'jpeg' | 'png' | 'webp-lossy' | 'webp-lossless'
  final int quality;
  final int width;
  final int height;
  final int originalSizeBytes;
  final int processedSizeBytes;
  final int metadataSizeBytes;
  final int base64SizeBytes;
  final int captureTimeMs;
  final int decodeTimeMs;
  final int resizeTimeMs;
  final int encodeTimeMs;
  final int metadataWriteTimeMs;
  final int metadataVerifyTimeMs;
  final int base64TimeMs;
  final int fileWriteTimeMs;
  final bool metadataPreserved;
  final int? multipartUploadMs;
  final int? base64UploadMs;
  final int totalTimeMs;

  const ImageBenchmarkResult({
    required this.format,
    required this.quality,
    required this.width,
    required this.height,
    required this.originalSizeBytes,
    required this.processedSizeBytes,
    required this.metadataSizeBytes,
    required this.base64SizeBytes,
    required this.captureTimeMs,
    required this.decodeTimeMs,
    required this.resizeTimeMs,
    required this.encodeTimeMs,
    required this.metadataWriteTimeMs,
    required this.metadataVerifyTimeMs,
    required this.base64TimeMs,
    required this.fileWriteTimeMs,
    required this.metadataPreserved,
    this.multipartUploadMs,
    this.base64UploadMs,
    required this.totalTimeMs,
  });

  double get reductionPercent => originalSizeBytes == 0 ? 0 : (1 - processedSizeBytes / originalSizeBytes) * 100;

  Map<String, dynamic> toJson() => {
        'format': format,
        'quality': quality,
        'width': width,
        'height': height,
        'originalSizeBytes': originalSizeBytes,
        'processedSizeBytes': processedSizeBytes,
        'metadataSizeBytes': metadataSizeBytes,
        'base64SizeBytes': base64SizeBytes,
        'captureTimeMs': captureTimeMs,
        'decodeTimeMs': decodeTimeMs,
        'resizeTimeMs': resizeTimeMs,
        'encodeTimeMs': encodeTimeMs,
        'metadataWriteTimeMs': metadataWriteTimeMs,
        'metadataVerifyTimeMs': metadataVerifyTimeMs,
        'base64TimeMs': base64TimeMs,
        'fileWriteTimeMs': fileWriteTimeMs,
        'metadataPreserved': metadataPreserved,
        'multipartUploadMs': multipartUploadMs,
        'base64UploadMs': base64UploadMs,
        'totalTimeMs': totalTimeMs,
        'reductionPercent': reductionPercent,
      };
}

class BenchmarkRun {
  final String id;
  final DateTime startedAt;
  final String device;
  final String cameraFacing;
  final String sourceResolution;
  final List<ImageBenchmarkResult> results;

  const BenchmarkRun({
    required this.id,
    required this.startedAt,
    required this.device,
    required this.cameraFacing,
    required this.sourceResolution,
    required this.results,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'device': device,
        'camera': cameraFacing,
        'sourceResolution': sourceResolution,
        'results': results.map((r) => r.toJson()).toList(),
      };
}
