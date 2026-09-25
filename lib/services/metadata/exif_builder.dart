import 'dart:typed_data';

import 'exif_tags.dart';
import 'tiff.dart';

/// Everything this app knows about one captured/processed image, gathered
/// BEFORE encoding, and turned into a raw TIFF/EXIF block by [ExifBuilder].
///
/// This is the single input to metadata embedding. Nothing here is ever
/// sent to the server as the primary metadata store — it goes into the
/// image file itself (see requirement #3 of the spec).
class CaptureMetadata {
  final double? latitude;
  final double? longitude;
  final double? altitudeMeters;
  final double? gpsAccuracyMeters;
  final DateTime? gpsTimestampUtc;

  final DateTime captureTime; // local capture time, with its own UTC offset
  final Duration utcOffset;

  final String? cameraMake; // device manufacturer (e.g. "samsung" -> "Samsung")
  final String? cameraModel; // device model (e.g. "SM-S928B")
  final String? lensFacing; // "front" | "back" (mapped to LensModel text; no non-standard tag)
  final String software;

  final int orientation; // EXIF orientation value (1..8)
  final int width;
  final int height;

  final double? exposureTimeSeconds;
  final double? fNumber;
  final int? iso;
  final double? focalLengthMm;

  final int? dpi; // null = do not write resolution tags at all

  const CaptureMetadata({
    this.latitude,
    this.longitude,
    this.altitudeMeters,
    this.gpsAccuracyMeters,
    this.gpsTimestampUtc,
    required this.captureTime,
    required this.utcOffset,
    this.cameraMake,
    this.cameraModel,
    this.lensFacing,
    this.software = 'Camera Lab 1.0',
    required this.orientation,
    required this.width,
    required this.height,
    this.exposureTimeSeconds,
    this.fNumber,
    this.iso,
    this.focalLengthMm,
    this.dpi,
  });

  bool get hasGps => latitude != null && longitude != null;

  CaptureMetadata copyWith({
    double? latitude,
    double? longitude,
    double? altitudeMeters,
    bool clearGps = false,
    int? orientation,
    int? width,
    int? height,
    int? dpi,
    bool clearDpi = false,
  }) {
    return CaptureMetadata(
      latitude: clearGps ? null : (latitude ?? this.latitude),
      longitude: clearGps ? null : (longitude ?? this.longitude),
      altitudeMeters: clearGps ? null : (altitudeMeters ?? this.altitudeMeters),
      gpsAccuracyMeters: clearGps ? null : gpsAccuracyMeters,
      gpsTimestampUtc: clearGps ? null : gpsTimestampUtc,
      captureTime: captureTime,
      utcOffset: utcOffset,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      lensFacing: lensFacing,
      software: software,
      orientation: orientation ?? this.orientation,
      width: width ?? this.width,
      height: height ?? this.height,
      exposureTimeSeconds: exposureTimeSeconds,
      fNumber: fNumber,
      iso: iso,
      focalLengthMm: focalLengthMm,
      dpi: clearDpi ? null : (dpi ?? this.dpi),
    );
  }
}

String _fmtExifDate(DateTime dt) {
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}:${p2(dt.month)}:${p2(dt.day)} ${p2(dt.hour)}:${p2(dt.minute)}:${p2(dt.second)}';
}

String _fmtOffset(Duration d) {
  final sign = d.isNegative ? '-' : '+';
  final abs = d.abs();
  final h = abs.inHours.toString().padLeft(2, '0');
  final m = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return '$sign$h:$m';
}

List<Rational> _dmsFromDecimalDegrees(double value) {
  final abs = value.abs();
  final deg = abs.floor();
  final minFloat = (abs - deg) * 60;
  final min = minFloat.floor();
  final secFloat = (minFloat - min) * 60;
  // 4 decimal places of arc-second precision, matching real camera EXIF.
  final secRational = Rational((secFloat * 10000).round(), 10000);
  return [Rational(deg, 1), Rational(min, 1), secRational];
}

/// Turns [CaptureMetadata] into a raw TIFF/EXIF block ready to embed.
class ExifBuilder {
  static Uint8List build(CaptureMetadata m) {
    final ifd0 = <int, IfdEntry>{
      ExifTag.orientation: IfdEntry(ExifTag.orientation, TiffType.short, 1, [m.orientation]),
      ExifTag.dateTime: IfdEntry(ExifTag.dateTime, TiffType.ascii, 0, _fmtExifDate(m.captureTime)),
      ExifTag.software: IfdEntry(ExifTag.software, TiffType.ascii, 0, m.software),
    };
    if (m.cameraMake != null && m.cameraMake!.isNotEmpty) {
      ifd0[ExifTag.make] = IfdEntry(ExifTag.make, TiffType.ascii, 0, m.cameraMake!);
    }
    if (m.cameraModel != null && m.cameraModel!.isNotEmpty) {
      ifd0[ExifTag.model] = IfdEntry(ExifTag.model, TiffType.ascii, 0, m.cameraModel!);
    }
    if (m.dpi != null) {
      ifd0[ExifTag.xResolution] = IfdEntry(ExifTag.xResolution, TiffType.rational, 1, [Rational(m.dpi!, 1)]);
      ifd0[ExifTag.yResolution] = IfdEntry(ExifTag.yResolution, TiffType.rational, 1, [Rational(m.dpi!, 1)]);
      ifd0[ExifTag.resolutionUnit] = IfdEntry(ExifTag.resolutionUnit, TiffType.short, 1, [2]); // inches
    }

    final exif = <int, IfdEntry>{
      ExifTag.dateTimeOriginal: IfdEntry(ExifTag.dateTimeOriginal, TiffType.ascii, 0, _fmtExifDate(m.captureTime)),
      ExifTag.dateTimeDigitized: IfdEntry(ExifTag.dateTimeDigitized, TiffType.ascii, 0, _fmtExifDate(m.captureTime)),
      ExifTag.offsetTimeOriginal: IfdEntry(ExifTag.offsetTimeOriginal, TiffType.ascii, 0, _fmtOffset(m.utcOffset)),
      ExifTag.offsetTime: IfdEntry(ExifTag.offsetTime, TiffType.ascii, 0, _fmtOffset(m.utcOffset)),
      ExifTag.subSecTimeOriginal:
          IfdEntry(ExifTag.subSecTimeOriginal, TiffType.ascii, 0, m.captureTime.millisecond.toString().padLeft(3, '0')),
      ExifTag.pixelXDimension: IfdEntry(ExifTag.pixelXDimension, TiffType.long, 1, [m.width]),
      ExifTag.pixelYDimension: IfdEntry(ExifTag.pixelYDimension, TiffType.long, 1, [m.height]),
    };
    if (m.exposureTimeSeconds != null) {
      // Store as a proper fraction (e.g. 1/120s), not a rounded decimal.
      final denom = m.exposureTimeSeconds! > 0 ? (1 / m.exposureTimeSeconds!).round() : 1;
      exif[ExifTag.exposureTime] = IfdEntry(ExifTag.exposureTime, TiffType.rational, 1, [Rational(1, denom)]);
    }
    if (m.fNumber != null) {
      exif[ExifTag.fNumber] = IfdEntry(ExifTag.fNumber, TiffType.rational, 1, [Rational.fromDouble(m.fNumber!, denominator: 10)]);
    }
    if (m.iso != null) {
      exif[ExifTag.isoSpeedRatings] = IfdEntry(ExifTag.isoSpeedRatings, TiffType.short, 1, [m.iso!]);
    }
    if (m.focalLengthMm != null) {
      exif[ExifTag.focalLength] =
          IfdEntry(ExifTag.focalLength, TiffType.rational, 1, [Rational.fromDouble(m.focalLengthMm!, denominator: 10)]);
    }
    if (m.lensFacing != null) {
      final label = m.lensFacing == 'front' ? 'Front Camera' : 'Back Camera';
      exif[ExifTag.lensModel] = IfdEntry(ExifTag.lensModel, TiffType.ascii, 0, label);
    }

    final gps = <int, IfdEntry>{};
    if (m.hasGps) {
      gps[ExifTag.gpsVersionId] = const IfdEntry(ExifTag.gpsVersionId, TiffType.byte, 4, [2, 3, 0, 0]);
      gps[ExifTag.gpsLatitudeRef] = IfdEntry(ExifTag.gpsLatitudeRef, TiffType.ascii, 0, m.latitude! >= 0 ? 'N' : 'S');
      gps[ExifTag.gpsLatitude] = IfdEntry(ExifTag.gpsLatitude, TiffType.rational, 3, _dmsFromDecimalDegrees(m.latitude!));
      gps[ExifTag.gpsLongitudeRef] = IfdEntry(ExifTag.gpsLongitudeRef, TiffType.ascii, 0, m.longitude! >= 0 ? 'E' : 'W');
      gps[ExifTag.gpsLongitude] = IfdEntry(ExifTag.gpsLongitude, TiffType.rational, 3, _dmsFromDecimalDegrees(m.longitude!));
      if (m.altitudeMeters != null) {
        gps[ExifTag.gpsAltitudeRef] = IfdEntry(ExifTag.gpsAltitudeRef, TiffType.byte, 1, [m.altitudeMeters! < 0 ? 1 : 0]);
        gps[ExifTag.gpsAltitude] =
            IfdEntry(ExifTag.gpsAltitude, TiffType.rational, 1, [Rational.fromDouble(m.altitudeMeters!.abs(), denominator: 100)]);
      }
      if (m.gpsAccuracyMeters != null) {
        gps[ExifTag.gpsHPositioningError] = IfdEntry(
            ExifTag.gpsHPositioningError, TiffType.rational, 1, [Rational.fromDouble(m.gpsAccuracyMeters!, denominator: 100)]);
      }
      if (m.gpsTimestampUtc != null) {
        final t = m.gpsTimestampUtc!;
        gps[ExifTag.gpsDateStamp] = IfdEntry(
            ExifTag.gpsDateStamp, TiffType.ascii, 0,
            '${t.year.toString().padLeft(4, '0')}:${t.month.toString().padLeft(2, '0')}:${t.day.toString().padLeft(2, '0')}');
        gps[ExifTag.gpsTimeStamp] = IfdEntry(ExifTag.gpsTimeStamp, TiffType.rational, 3,
            [Rational(t.hour, 1), Rational(t.minute, 1), Rational(t.second, 1)]);
      }
    }

    final writer = TiffWriter(ifd0: ifd0, exif: exif, gps: gps);
    return writer.build();
  }
}
