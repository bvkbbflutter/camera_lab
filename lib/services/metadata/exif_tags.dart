/// EXIF/TIFF tag ids used by this module.
///
/// Only the tags this POC actually reads/writes are listed — see
/// requirement #3/#4 in the spec: "Do not write unsupported/custom fields
/// pretending they are standard EXIF fields."
library;

class ExifTag {
  // ---- IFD0 (main image) ----
  static const int imageWidth = 0x0100;
  static const int imageLength = 0x0101;
  static const int make = 0x010f;
  static const int model = 0x0110;
  static const int orientation = 0x0112;
  static const int xResolution = 0x011a;
  static const int yResolution = 0x011b;
  static const int resolutionUnit = 0x0128;
  static const int software = 0x0131;
  static const int dateTime = 0x0132;
  static const int exifIfdPointer = 0x8769;
  static const int gpsIfdPointer = 0x8825;

  // ---- Exif sub-IFD ----
  static const int exposureTime = 0x829a;
  static const int fNumber = 0x829d;
  static const int isoSpeedRatings = 0x8827;
  static const int exifVersion = 0x9000;
  static const int dateTimeOriginal = 0x9003;
  static const int dateTimeDigitized = 0x9004;
  static const int offsetTime = 0x9010;
  static const int offsetTimeOriginal = 0x9011;
  static const int subSecTimeOriginal = 0x9291;
  static const int focalLength = 0x920a;
  static const int pixelXDimension = 0xa002;
  static const int pixelYDimension = 0xa003;
  static const int lensMake = 0xa433;
  static const int lensModel = 0xa434;

  // ---- GPS sub-IFD ----
  static const int gpsVersionId = 0x0000;
  static const int gpsLatitudeRef = 0x0001;
  static const int gpsLatitude = 0x0002;
  static const int gpsLongitudeRef = 0x0003;
  static const int gpsLongitude = 0x0004;
  static const int gpsAltitudeRef = 0x0005;
  static const int gpsAltitude = 0x0006;
  static const int gpsTimeStamp = 0x0007;
  static const int gpsDateStamp = 0x001d;
  static const int gpsHPositioningError = 0x001f;
}

/// TIFF field types (see TIFF 6.0 spec §2).
class TiffType {
  static const int byte = 1;
  static const int ascii = 2;
  static const int short = 3;
  static const int long = 4;
  static const int rational = 5;
  static const int undefined = 7;
  static const int slong = 9;
  static const int srational = 10;

  static int sizeOf(int type) {
    switch (type) {
      case byte:
      case ascii:
      case undefined:
        return 1;
      case short:
        return 2;
      case long:
      case slong:
        return 4;
      case rational:
      case srational:
        return 8;
      default:
        return 1;
    }
  }
}

const Map<int, String> orientationLabels = {
  1: 'Normal (0°)',
  2: 'Mirrored horizontal',
  3: 'Rotated 180°',
  4: 'Mirrored vertical',
  5: 'Mirrored horizontal, rotated 270° CW',
  6: 'Rotated 90° CW',
  7: 'Mirrored horizontal, rotated 90° CW',
  8: 'Rotated 270° CW',
};
