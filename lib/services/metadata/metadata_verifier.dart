import 'dart:typed_data';

import 'metadata_models.dart';
import 'metadata_service.dart';

/// Implements requirement #20/#21/#61: after writing an output image, this
/// REOPENS the file and compares what actually made it into the bytes
/// against the original — it never simply assumes metadata survived.
class MetadataVerifier {
  static MetadataVerificationResult compare({
    required Uint8List originalBytes,
    required Uint8List outputBytes,
    required bool userRequestedGps,
    required bool userRequestedMetadata,
  }) {
    final original = MetadataService.inspect(originalBytes);
    final output = MetadataService.inspect(outputBytes);

    final fields = <FieldComparison>[
      _gpsField(original, output, userRequestedGps, userRequestedMetadata),
      _dateField(original, output, userRequestedMetadata),
      _cameraField(original, output, userRequestedMetadata),
      _orientationField(original, output, userRequestedMetadata),
      _dpiField(original, output, userRequestedMetadata),
      _resolutionField(original, output),
    ];

    final allOk = fields.every((f) =>
        f.status == FieldStatus.preserved ||
        f.status == FieldStatus.removedByUser ||
        f.status == FieldStatus.notPresentOriginally ||
        (f.status == FieldStatus.changed && f.label == 'Resolution'));

    return MetadataVerificationResult(fields: fields, allExpectedFieldsPreserved: allOk);
  }

  static FieldComparison _gpsField(
    ImageMetadataReport orig,
    ImageMetadataReport out,
    bool requested,
    bool metaRequested,
  ) {
    final origStr =
        orig.gps == null ? null : '${orig.gps!.latitude.toStringAsFixed(6)}, ${orig.gps!.longitude.toStringAsFixed(6)}';
    final outStr = out.gps == null ? null : '${out.gps!.latitude.toStringAsFixed(6)}, ${out.gps!.longitude.toStringAsFixed(6)}';

    if (orig.gps == null) {
      return FieldComparison(label: 'GPS', originalValue: null, outputValue: outStr, status: FieldStatus.notPresentOriginally);
    }
    if (!metaRequested || !requested) {
      return FieldComparison(label: 'GPS', originalValue: origStr, outputValue: outStr, status: FieldStatus.removedByUser);
    }
    if (out.gps == null) {
      return FieldComparison(label: 'GPS', originalValue: origStr, outputValue: null, status: FieldStatus.notSupportedByEncoder);
    }
    final closeEnough = (orig.gps!.latitude - out.gps!.latitude).abs() < 1e-4 && (orig.gps!.longitude - out.gps!.longitude).abs() < 1e-4;
    return FieldComparison(
      label: 'GPS',
      originalValue: origStr,
      outputValue: outStr,
      status: closeEnough ? FieldStatus.preserved : FieldStatus.changed,
    );
  }

  static FieldComparison _dateField(ImageMetadataReport orig, ImageMetadataReport out, bool metaRequested) {
    if (orig.capturedAtRaw == null) {
      return FieldComparison(
          label: 'Capture time', originalValue: null, outputValue: out.capturedAtRaw, status: FieldStatus.notPresentOriginally);
    }
    if (!metaRequested) {
      return FieldComparison(
          label: 'Capture time', originalValue: orig.capturedAtRaw, outputValue: out.capturedAtRaw, status: FieldStatus.removedByUser);
    }
    if (out.capturedAtRaw == null) {
      return FieldComparison(
          label: 'Capture time', originalValue: orig.capturedAtRaw, outputValue: null, status: FieldStatus.notSupportedByEncoder);
    }
    return FieldComparison(
      label: 'Capture time',
      originalValue: orig.capturedAtRaw,
      outputValue: out.capturedAtRaw,
      status: orig.capturedAtRaw == out.capturedAtRaw ? FieldStatus.preserved : FieldStatus.changed,
    );
  }

  static FieldComparison _cameraField(ImageMetadataReport orig, ImageMetadataReport out, bool metaRequested) {
    final origStr = orig.camera?.make == null && orig.camera?.model == null ? null : '${orig.camera?.make ?? ''} ${orig.camera?.model ?? ''}'.trim();
    final outStr = out.camera?.make == null && out.camera?.model == null ? null : '${out.camera?.make ?? ''} ${out.camera?.model ?? ''}'.trim();
    if (origStr == null || origStr.isEmpty) {
      return FieldComparison(label: 'Camera', originalValue: null, outputValue: outStr, status: FieldStatus.notPresentOriginally);
    }
    if (!metaRequested) {
      return FieldComparison(label: 'Camera', originalValue: origStr, outputValue: outStr, status: FieldStatus.removedByUser);
    }
    if (outStr == null || outStr.isEmpty) {
      return FieldComparison(label: 'Camera', originalValue: origStr, outputValue: null, status: FieldStatus.notSupportedByEncoder);
    }
    return FieldComparison(
      label: 'Camera',
      originalValue: origStr,
      outputValue: outStr,
      status: origStr == outStr ? FieldStatus.preserved : FieldStatus.changed,
    );
  }

  static FieldComparison _orientationField(ImageMetadataReport orig, ImageMetadataReport out, bool metaRequested) {
    if (orig.orientation == null) {
      return FieldComparison(
          label: 'Orientation',
          originalValue: null,
          outputValue: out.orientation?.label,
          status: FieldStatus.notPresentOriginally);
    }
    if (!metaRequested) {
      return FieldComparison(
          label: 'Orientation',
          originalValue: orig.orientation!.label,
          outputValue: out.orientation?.label,
          status: FieldStatus.removedByUser);
    }
    if (out.orientation == null) {
      return FieldComparison(
          label: 'Orientation', originalValue: orig.orientation!.label, outputValue: null, status: FieldStatus.notSupportedByEncoder);
    }
    return FieldComparison(
      label: 'Orientation',
      originalValue: orig.orientation!.label,
      outputValue: out.orientation!.label,
      status: orig.orientation!.value == out.orientation!.value ? FieldStatus.preserved : FieldStatus.changed,
    );
  }

  static FieldComparison _dpiField(ImageMetadataReport orig, ImageMetadataReport out, bool metaRequested) {
    final origStr = orig.dpi == null ? null : '${orig.dpi!.x.round()} DPI';
    final outStr = out.dpi == null ? null : '${out.dpi!.x.round()} DPI';
    if (orig.dpi == null && out.dpi == null) {
      return const FieldComparison(label: 'DPI', originalValue: null, outputValue: null, status: FieldStatus.notPresentOriginally);
    }
    if (out.dpi == null) {
      return FieldComparison(label: 'DPI', originalValue: origStr, outputValue: null, status: FieldStatus.notSupportedByEncoder);
    }
    if (orig.dpi == null) {
      // DPI was newly requested by the user for this run — not a loss.
      return FieldComparison(label: 'DPI', originalValue: null, outputValue: outStr, status: FieldStatus.changed);
    }
    return FieldComparison(
      label: 'DPI',
      originalValue: origStr,
      outputValue: outStr,
      status: (orig.dpi!.x - out.dpi!.x).abs() < 0.5 ? FieldStatus.preserved : FieldStatus.changed,
    );
  }

  static FieldComparison _resolutionField(ImageMetadataReport orig, ImageMetadataReport out) {
    final origStr = '${orig.width}×${orig.height}';
    final outStr = '${out.width}×${out.height}';
    return FieldComparison(
      label: 'Resolution',
      originalValue: origStr,
      outputValue: outStr,
      status: origStr == outStr ? FieldStatus.preserved : FieldStatus.changed,
    );
  }
}
