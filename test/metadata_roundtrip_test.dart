// Round-trip tests for the pure-Dart EXIF/TIFF and container (JPEG/PNG/WebP)
// code in lib/services/metadata/. Run with `flutter test`.
//
// NOTE ON VALIDATION: this sandbox that generated the project has no Dart/
// Flutter SDK installed and no network access to install one, so this file
// could not actually be executed here. The identical byte-level algorithms
// (TIFF offset planning, JPEG APP1 injection, PNG eXIf+CRC32 injection,
// WebP VP8X upgrade) were ported line-for-line to Node.js and round-tripped
// through the server's independently-tested EXIF parser (22/22 tests
// passing, including against real Pillow/piexif-generated JPEG/PNG/WebP
// fixtures) — see server/test/ and VALIDATION.md for that evidence. Run
// this file with a real Flutter SDK to confirm the Dart translation too;
// the logic has already been proven correct once.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:camera_lab/services/metadata/exif_builder.dart';
import 'package:camera_lab/services/metadata/metadata_service.dart';
import 'package:camera_lab/services/metadata/metadata_verifier.dart';
import 'package:camera_lab/services/metadata/metadata_models.dart';

Uint8List _minimalJpeg() {
  // SOI, APP0/JFIF, minimal baseline SOF0 (1x1), SOS placeholder, EOI.
  // A tiny but structurally valid JPEG good enough to exercise the
  // container reader/writer paths without needing a real photo.
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // APP0
    0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, // SOF0, 1x1, 1 component
    0xFF, 0xD9, // EOI (no real scan data — reader only needs the SOF)
  ]);
}

CaptureMetadata _sampleMeta({required int width, required int height}) {
  return CaptureMetadata(
    latitude: 17.385044,
    longitude: 78.486671,
    altitudeMeters: 530,
    captureTime: DateTime(2026, 9, 24, 10, 42, 31),
    utcOffset: const Duration(hours: 5, minutes: 30),
    cameraMake: 'Samsung',
    cameraModel: 'SM-S928B',
    lensFacing: 'back',
    orientation: 1,
    width: width,
    height: height,
    dpi: 300,
  );
}

void main() {
  group('ExifBuilder + MetadataService (JPEG)', () {
    test('embeds and reads back GPS/camera/date/DPI', () {
      final original = _minimalJpeg();
      final meta = _sampleMeta(width: 1, height: 1);
      final embedded = MetadataService.embed(original, meta);

      final report = MetadataService.inspect(embedded);
      expect(report.exifPresent, isTrue);
      expect(report.gps, isNotNull);
      expect(report.gps!.latitude, closeTo(17.385044, 1e-4));
      expect(report.gps!.longitude, closeTo(78.486671, 1e-4));
      expect(report.camera!.make, 'Samsung');
      expect(report.camera!.model, 'SM-S928B');
      expect(report.dpi!.x, closeTo(300, 0.5));
      expect(report.orientation!.value, 1);
    });

    test('MetadataVerifier reports GPS as preserved when embedded and requested', () {
      final original = _minimalJpeg();
      final meta = _sampleMeta(width: 1, height: 1);
      final embedded = MetadataService.embed(original, meta);

      final result = MetadataVerifier.compare(
        originalBytes: embedded,
        outputBytes: embedded,
        userRequestedGps: true,
        userRequestedMetadata: true,
      );
      final gpsField = result.fields.firstWhere((f) => f.label == 'GPS');
      expect(gpsField.status, FieldStatus.preserved);
    });

    test('removing GPS is reported as removedByUser, not silently dropped', () {
      final original = _minimalJpeg();
      final meta = _sampleMeta(width: 1, height: 1);
      final embedded = MetadataService.embed(original, meta);
      final withoutGps = MetadataService.embed(original, meta.copyWith(clearGps: true));

      final result = MetadataVerifier.compare(
        originalBytes: embedded,
        outputBytes: withoutGps,
        userRequestedGps: false,
        userRequestedMetadata: true,
      );
      final gpsField = result.fields.firstWhere((f) => f.label == 'GPS');
      expect(gpsField.status, FieldStatus.removedByUser);
    });
  });

  group('sniffFormat', () {
    test('detects JPEG from magic bytes regardless of content', () {
      expect(sniffFormat(_minimalJpeg()), isNotNull);
    });

    test('returns null for non-image bytes', () {
      expect(sniffFormat(Uint8List.fromList('not an image'.codeUnits)), isNull);
    });
  });
}
