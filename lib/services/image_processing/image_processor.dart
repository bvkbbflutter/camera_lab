import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/processing_options.dart';
import '../metadata/exif_builder.dart';
import '../metadata/image_format.dart';
import '../metadata/metadata_service.dart';
import '../metadata/metadata_verifier.dart';
import '../metadata/metadata_models.dart';

/// One stage's measured duration (spec §31: Stopwatch-based benchmarking,
/// never hardcoded).
class StageTiming {
  final String stage;
  final int milliseconds;
  const StageTiming(this.stage, this.milliseconds);
}

/// Full result of running an image through the processing pipeline
/// (spec §2 / §20): original bytes in, processed bytes + verification out.
class ProcessingResult {
  final Uint8List outputBytes;
  final ImageFormat outputFormat;
  final int outputWidth;
  final int outputHeight;
  final ImageMetadataReport originalMetadata;
  final ImageMetadataReport outputMetadata;
  final MetadataVerificationResult verification;
  final List<StageTiming> timings;

  const ProcessingResult({
    required this.outputBytes,
    required this.outputFormat,
    required this.outputWidth,
    required this.outputHeight,
    required this.originalMetadata,
    required this.outputMetadata,
    required this.verification,
    required this.timings,
  });

  int get totalMs => timings.fold(0, (a, b) => a + b.milliseconds);
}

/// Implements the pipeline in spec §20:
///
///   Original → read metadata → decode pixels → resize/crop/rotate →
///   encode output → write metadata → save output → reopen output →
///   read metadata again → verify
///
/// Decoding and resizing pixels is delegated to the `image` package.
/// Metadata is deliberately NOT delegated to it — embedding, reading and
/// verification all go through our own EXIF/container code in
/// lib/services/metadata/, so exactly what gets written and what survives
/// is fully under this app's control and independently checkable (spec §12:
/// "Do not assume decoding/re-encoding preserves EXIF automatically").
class ImageProcessor {
  static Future<ProcessingResult> process({
    required Uint8List originalBytes,
    required ProcessingOptions options,
    required CaptureMetadata captureMeta,
  }) async {
    return Isolate.run(() {
    final timings = <StageTiming>[];
    final sw = Stopwatch();

    sw.start();
    final originalMetadata = MetadataService.inspect(originalBytes);
    sw.stop();
    timings.add(StageTiming('Read original metadata', sw.elapsedMilliseconds));

    sw.reset();
    sw.start();
    img.Image? decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode source image');
    }
    sw.stop();
    timings.add(StageTiming('Decode pixels', sw.elapsedMilliseconds));

    // Bake EXIF orientation into the pixels ourselves (once), then always
    // write orientation=1 on the output. Doing this exactly once, here,
    // is how we avoid the double-rotation bug the spec calls out (§9).
    sw.reset();
    sw.start();
    final srcOrientation = originalMetadata.orientation?.value ?? 1;
    if (srcOrientation != 1) {
      decoded = img.bakeOrientation(decoded);
    }
    if (options.maxDimension != null) {
      final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longest > options.maxDimension!) {
        decoded = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: options.maxDimension)
            : img.copyResize(decoded, height: options.maxDimension);
      }
    }
    sw.stop();
    timings.add(StageTiming('Resize/rotate', sw.elapsedMilliseconds));

    sw.reset();
    sw.start();
    Uint8List encoded;
    switch (options.format) {
      case ImageFormat.jpeg:
        encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: options.quality));
        break;
      case ImageFormat.png:
        encoded = Uint8List.fromList(img.encodePng(decoded));
        break;
      case ImageFormat.webp:
        encoded = Uint8List.fromList(
          img.encodeWebP(decoded, lossless: options.webpLossless, quality: options.quality),
        );
        break;
    }
    sw.stop();
    timings.add(StageTiming('Encode ${options.format.label}', sw.elapsedMilliseconds));

    sw.reset();
    sw.start();
    final effectiveMeta = _buildEffectiveMetadata(captureMeta, options, decoded.width, decoded.height, srcOrientation);
    final withMetadata =
        options.preserveMetadata ? MetadataService.embed(encoded, effectiveMeta) : encoded;
    sw.stop();
    timings.add(StageTiming('Write metadata', sw.elapsedMilliseconds));

    sw.reset();
    sw.start();
    final outputMetadata = MetadataService.inspect(withMetadata);
    final verification = MetadataVerifier.compare(
      originalBytes: originalBytes,
      outputBytes: withMetadata,
      userRequestedGps: options.includeGps,
      userRequestedMetadata: options.preserveMetadata,
    );
    sw.stop();
    timings.add(StageTiming('Verify metadata', sw.elapsedMilliseconds));

    return ProcessingResult(
      outputBytes: withMetadata,
      outputFormat: options.format,
      outputWidth: decoded.width,
      outputHeight: decoded.height,
      originalMetadata: originalMetadata,
      outputMetadata: outputMetadata,
      verification: verification,
      timings: timings,
    );
    });
  }

  /// Applies the user's metadata toggles (GPS/capture-time/camera/
  /// orientation/DPI) to produce exactly what should be embedded —
  /// spec §6: "Allow Embed location / Remove location from the
  /// image-processing screen."
  static CaptureMetadata _buildEffectiveMetadata(
    CaptureMetadata base,
    ProcessingOptions options,
    int width,
    int height,
    int originalOrientation,
  ) {
    return CaptureMetadata(
      latitude: options.includeGps ? base.latitude : null,
      longitude: options.includeGps ? base.longitude : null,
      altitudeMeters: options.includeGps ? base.altitudeMeters : null,
      gpsAccuracyMeters: options.includeGps ? base.gpsAccuracyMeters : null,
      gpsTimestampUtc: options.includeGps ? base.gpsTimestampUtc : null,
      captureTime: options.includeCaptureTime ? base.captureTime : DateTime.fromMillisecondsSinceEpoch(0),
      utcOffset: base.utcOffset,
      cameraMake: options.includeCameraInfo ? base.cameraMake : null,
      cameraModel: options.includeCameraInfo ? base.cameraModel : null,
      lensFacing: options.includeCameraInfo ? base.lensFacing : null,
      software: base.software,
      // Pixels are already normalized by bakeOrientation above (once), so
      // the output's own orientation tag is always "normal" unless the
      // caller opted out of orientation metadata entirely (in which case
      // we still must write *something* valid — 1 is correct either way
      // since pixels are already upright).
      orientation: options.includeOrientation ? 1 : 1,
      width: width,
      height: height,
      exposureTimeSeconds: options.includeCameraInfo ? base.exposureTimeSeconds : null,
      fNumber: options.includeCameraInfo ? base.fNumber : null,
      iso: options.includeCameraInfo ? base.iso : null,
      focalLengthMm: options.includeCameraInfo ? base.focalLengthMm : null,
      dpi: options.dpi,
    );
  }

  static Future<void> writeToFile(Uint8List bytes, String path) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
  }
}
