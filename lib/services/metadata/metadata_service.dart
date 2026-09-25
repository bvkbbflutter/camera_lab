import 'dart:typed_data';

import 'exif_builder.dart';
import 'exif_tags.dart';
import 'image_format.dart';
import 'jpeg_container.dart';
import 'metadata_models.dart';
import 'png_container.dart';
import 'tiff.dart';
import 'webp_container.dart';

/// Detects the real format from magic bytes — never trusts a file
/// extension or an assumed MIME type.
ImageFormat? sniffFormat(Uint8List bytes) {
  if (bytes.length < 12) return null;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return ImageFormat.jpeg;
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return ImageFormat.png;
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return ImageFormat.webp;
  }
  return null;
}

/// The single entry point for embedding metadata into an image and for
/// reading it back out, across JPEG/PNG/WebP. This is where the pipeline
/// step "Embed metadata into image" (spec §2) and the read side of
/// "Image Details" (spec §15) both live.
class MetadataService {
  /// Embeds [meta] into [imageBytes] (whose format is auto-detected),
  /// returning a new file with the same pixels and a freshly-written
  /// EXIF/GPS block. The original bytes are never mutated in place.
  static Uint8List embed(Uint8List imageBytes, CaptureMetadata meta) {
    final format = sniffFormat(imageBytes);
    if (format == null) {
      throw const FormatException('Cannot embed metadata: unrecognized image format');
    }
    final tiff = ExifBuilder.build(meta);
    switch (format) {
      case ImageFormat.jpeg:
        return JpegContainer.embed(imageBytes, tiff);
      case ImageFormat.png:
        return PngContainer.embed(imageBytes, exifBytes: tiff, dpi: meta.dpi);
      case ImageFormat.webp:
        return WebpContainer.embed(imageBytes, tiff);
    }
  }

  /// Reads back everything embedded in [imageBytes] — the same operation
  /// the server performs on upload, done locally for immediate display.
  static ImageMetadataReport inspect(Uint8List imageBytes) {
    final format = sniffFormat(imageBytes);
    if (format == null) {
      throw const FormatException('File is not a JPEG, PNG or WebP image');
    }

    switch (format) {
      case ImageFormat.jpeg:
        final info = JpegContainer.read(imageBytes);
        return _reportFrom(
          format: format,
          width: info.width,
          height: info.height,
          fileSize: imageBytes.length,
          rawExif: info.exif,
          metadataBytes: info.metadataBytes,
        );
      case ImageFormat.png:
        final info = PngContainer.read(imageBytes);
        var report = _reportFrom(
          format: format,
          width: info.width,
          height: info.height,
          fileSize: imageBytes.length,
          rawExif: info.exif,
          metadataBytes: info.metadataBytes,
        );
        // PNG can carry density via pHYs even with no EXIF at all.
        if (report.dpi == null && info.phys != null && info.phys!.isMeters) {
          final dpiX = info.phys!.xPpu * 0.0254;
          final dpiY = info.phys!.yPpu * 0.0254;
          report = ImageMetadataReport(
            format: report.format,
            width: report.width,
            height: report.height,
            fileSizeBytes: report.fileSizeBytes,
            exifPresent: report.exifPresent,
            exifSizeBytes: report.exifSizeBytes,
            metadataBytes: report.metadataBytes,
            gps: report.gps,
            capturedAt: report.capturedAt,
            capturedAtRaw: report.capturedAtRaw,
            camera: report.camera,
            orientation: report.orientation,
            dpi: DpiInfo(x: dpiX, y: dpiY, source: 'pHYs'),
          );
        }
        return report;
      case ImageFormat.webp:
        final info = WebpContainer.read(imageBytes);
        final report = _reportFrom(
          format: format,
          width: info.width,
          height: info.height,
          fileSize: imageBytes.length,
          rawExif: info.exif,
          metadataBytes: info.metadataBytes,
        );
        return ImageMetadataReport(
          format: report.format,
          width: report.width,
          height: report.height,
          fileSizeBytes: report.fileSizeBytes,
          exifPresent: report.exifPresent,
          exifSizeBytes: report.exifSizeBytes,
          metadataBytes: report.metadataBytes,
          gps: report.gps,
          capturedAt: report.capturedAt,
          capturedAtRaw: report.capturedAtRaw,
          camera: report.camera,
          orientation: report.orientation,
          dpi: report.dpi,
          webpEncoding: info.encoding,
        );
    }
  }

  static ImageMetadataReport _reportFrom({
    required ImageFormat format,
    required int width,
    required int height,
    required int fileSize,
    required Uint8List? rawExif,
    required int metadataBytes,
  }) {
    if (rawExif == null || rawExif.length < 8) {
      return ImageMetadataReport(
        format: format,
        width: width,
        height: height,
        fileSizeBytes: fileSize,
        exifPresent: false,
        exifSizeBytes: 0,
        metadataBytes: metadataBytes,
      );
    }

    TiffData tiff;
    try {
      tiff = TiffReader.parse(rawExif);
    } catch (_) {
      return ImageMetadataReport(
        format: format,
        width: width,
        height: height,
        fileSizeBytes: fileSize,
        exifPresent: false,
        exifSizeBytes: rawExif.length,
        metadataBytes: metadataBytes,
      );
    }

    final gpsLatRef = tiff.gps[ExifTag.gpsLatitudeRef]?.asString;
    final gpsLonRef = tiff.gps[ExifTag.gpsLongitudeRef]?.asString;
    final lat = _dmsToDecimal(tiff.gps[ExifTag.gpsLatitude]?.asRationalList, gpsLatRef);
    final lon = _dmsToDecimal(tiff.gps[ExifTag.gpsLongitude]?.asRationalList, gpsLonRef);
    GpsMetadata? gps;
    if (lat != null && lon != null) {
      final altRef = tiff.gps[ExifTag.gpsAltitudeRef]?.asInt;
      var alt = tiff.gps[ExifTag.gpsAltitude]?.asDouble;
      if (alt != null && altRef == 1) alt = -alt;
      gps = GpsMetadata(
        latitude: lat,
        longitude: lon,
        altitudeMeters: alt,
        accuracyMeters: tiff.gps[ExifTag.gpsHPositioningError]?.asDouble,
      );
    }

    final dateOriginal = tiff.exif[ExifTag.dateTimeOriginal]?.asString ?? tiff.ifd0[ExifTag.dateTime]?.asString;
    final offset = tiff.exif[ExifTag.offsetTimeOriginal]?.asString;
    final capturedAt = _parseExifDate(dateOriginal, offset);

    final make = tiff.ifd0[ExifTag.make]?.asString;
    final model = tiff.ifd0[ExifTag.model]?.asString;
    CameraMetadataInfo? camera;
    if (make != null || model != null || tiff.exif.isNotEmpty) {
      camera = CameraMetadataInfo(
        make: make,
        model: model,
        lensModel: tiff.exif[ExifTag.lensModel]?.asString,
        software: tiff.ifd0[ExifTag.software]?.asString,
        exposureTimeSeconds: tiff.exif[ExifTag.exposureTime]?.asDouble,
        fNumber: tiff.exif[ExifTag.fNumber]?.asDouble,
        iso: tiff.exif[ExifTag.isoSpeedRatings]?.asInt,
        focalLengthMm: tiff.exif[ExifTag.focalLength]?.asDouble,
      );
    }

    OrientationInfo? orientation;
    final orientVal = tiff.ifd0[ExifTag.orientation]?.asInt;
    if (orientVal != null) {
      orientation = OrientationInfo(value: orientVal, label: orientationLabels[orientVal] ?? 'Unknown');
    }

    DpiInfo? dpi;
    final xRes = tiff.ifd0[ExifTag.xResolution]?.asDouble;
    final yRes = tiff.ifd0[ExifTag.yResolution]?.asDouble;
    final resUnit = tiff.ifd0[ExifTag.resolutionUnit]?.asInt;
    if (xRes != null && (resUnit == 2 || resUnit == null)) {
      dpi = DpiInfo(x: xRes, y: yRes ?? xRes, source: 'exif');
    } else if (xRes != null && resUnit == 3) {
      dpi = DpiInfo(x: xRes * 2.54, y: (yRes ?? xRes) * 2.54, source: 'exif');
    }

    return ImageMetadataReport(
      format: format,
      width: width,
      height: height,
      fileSizeBytes: fileSize,
      exifPresent: true,
      exifSizeBytes: rawExif.length,
      metadataBytes: metadataBytes,
      gps: gps,
      capturedAt: capturedAt,
      capturedAtRaw: dateOriginal,
      camera: camera,
      orientation: orientation,
      dpi: dpi,
    );
  }

  static double? _dmsToDecimal(List<Rational>? dms, String? ref) {
    if (dms == null || dms.length < 3) return null;
    final deg = dms[0].toDouble();
    final min = dms[1].toDouble();
    final sec = dms[2].toDouble();
    var value = deg + min / 60 + sec / 3600;
    if (ref == 'S' || ref == 'W') value = -value;
    return value;
  }

  static DateTime? _parseExifDate(String? dt, String? offset) {
    if (dt == null) return null;
    final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(dt);
    if (m == null) return null;
    final iso =
        '${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${(offset != null && RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(offset)) ? offset : ''}';
    return DateTime.tryParse(iso);
  }
}
