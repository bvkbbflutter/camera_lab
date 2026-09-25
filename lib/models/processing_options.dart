import '../services/metadata/image_format.dart';

/// Spec §19: the knobs exposed on the Image Processing screen.
class ProcessingOptions {
  final ImageFormat format;
  final bool webpLossless; // only meaningful when format == webp
  final int quality; // 10..100 (ignored for PNG and lossless WebP)
  final int? maxDimension; // null = original size, else longest-side cap
  final bool preserveMetadata; // master switch
  final bool includeGps;
  final bool includeCaptureTime;
  final bool includeCameraInfo;
  final bool includeOrientation;
  final int? dpi; // null = do not write resolution tags

  const ProcessingOptions({
    this.format = ImageFormat.jpeg,
    this.webpLossless = false,
    this.quality = 85,
    this.maxDimension = 1920,
    this.preserveMetadata = true,
    this.includeGps = true,
    this.includeCaptureTime = true,
    this.includeCameraInfo = true,
    this.includeOrientation = true,
    this.dpi = 300,
  });

  ProcessingOptions copyWith({
    ImageFormat? format,
    bool? webpLossless,
    int? quality,
    int? maxDimension,
    bool clearMaxDimension = false,
    bool? preserveMetadata,
    bool? includeGps,
    bool? includeCaptureTime,
    bool? includeCameraInfo,
    bool? includeOrientation,
    int? dpi,
    bool clearDpi = false,
  }) {
    return ProcessingOptions(
      format: format ?? this.format,
      webpLossless: webpLossless ?? this.webpLossless,
      quality: quality ?? this.quality,
      maxDimension: clearMaxDimension ? null : (maxDimension ?? this.maxDimension),
      preserveMetadata: preserveMetadata ?? this.preserveMetadata,
      includeGps: includeGps ?? this.includeGps,
      includeCaptureTime: includeCaptureTime ?? this.includeCaptureTime,
      includeCameraInfo: includeCameraInfo ?? this.includeCameraInfo,
      includeOrientation: includeOrientation ?? this.includeOrientation,
      dpi: clearDpi ? null : (dpi ?? this.dpi),
    );
  }

  static const List<int> resizeOptions = [4096, 3840, 2560, 1920, 1600, 1280, 1024, 800, 640];
  static const List<int> dpiOptions = [72, 96, 150, 300, 600];
  static const List<int> qualityPresets = [50, 60, 70, 75, 80, 85, 90, 95, 100];
}
