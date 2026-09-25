import 'image_format.dart';

/// GPS metadata as decoded from an image file. Every field reflects
/// exactly what was embedded — no field is fabricated when absent.
class GpsMetadata {
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? accuracyMeters;

  const GpsMetadata({required this.latitude, required this.longitude, this.altitudeMeters, this.accuracyMeters});
}

class CameraMetadataInfo {
  final String? make;
  final String? model;
  final String? lensModel;
  final String? software;
  final double? exposureTimeSeconds;
  final double? fNumber;
  final int? iso;
  final double? focalLengthMm;

  const CameraMetadataInfo({
    this.make,
    this.model,
    this.lensModel,
    this.software,
    this.exposureTimeSeconds,
    this.fNumber,
    this.iso,
    this.focalLengthMm,
  });
}

class DpiInfo {
  final double x;
  final double y;
  final String source; // 'exif' | 'jfif' | 'pHYs'

  const DpiInfo({required this.x, required this.y, required this.source});
}

class OrientationInfo {
  final int value;
  final String label;

  const OrientationInfo({required this.value, required this.label});
}

/// Full result of inspecting one image file — everything the "Image
/// Details" screen (spec #15/#45) shows, read directly from the file's
/// own embedded metadata rather than a side-channel JSON object.
class ImageMetadataReport {
  final ImageFormat format;
  final int width;
  final int height;
  final int fileSizeBytes;
  final bool exifPresent;
  final int exifSizeBytes;
  final int metadataBytes;
  final GpsMetadata? gps;
  final DateTime? capturedAt;
  final String? capturedAtRaw;
  final CameraMetadataInfo? camera;
  final OrientationInfo? orientation;
  final DpiInfo? dpi;
  final String? webpEncoding; // 'lossy' | 'lossless', WebP only

  const ImageMetadataReport({
    required this.format,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.exifPresent,
    required this.exifSizeBytes,
    required this.metadataBytes,
    this.gps,
    this.capturedAt,
    this.capturedAtRaw,
    this.camera,
    this.orientation,
    this.dpi,
    this.webpEncoding,
  });
}

/// One field's before/after state in the metadata-preservation comparison
/// screen (spec #22): whether it survived processing unchanged, changed
/// (e.g. resolution after a resize), or was dropped entirely.
enum FieldStatus { preserved, changed, removedByUser, notSupportedByEncoder, notPresentOriginally }

class FieldComparison {
  final String label;
  final String? originalValue;
  final String? outputValue;
  final FieldStatus status;

  const FieldComparison({required this.label, this.originalValue, this.outputValue, required this.status});
}

/// The full original-vs-output comparison used by both the Processing
/// Result screen (#48) and the dedicated Metadata Comparison screen (#22).
class MetadataVerificationResult {
  final List<FieldComparison> fields;
  final bool allExpectedFieldsPreserved;

  const MetadataVerificationResult({required this.fields, required this.allExpectedFieldsPreserved});
}
