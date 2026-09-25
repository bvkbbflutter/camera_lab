import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../core/format_utils.dart';
import '../../models/image_asset.dart';
import '../../models/processing_options.dart';
import '../../models/upload_task.dart';
import '../../services/image_processing/image_processor.dart';
import '../../services/metadata/exif_builder.dart';
import '../../services/metadata/image_format.dart';
import '../../services/metadata/metadata_service.dart';
import '../../widgets/field_comparison_row.dart';

/// Spec §19/§47/§48: the Image Processing screen — format, quality, resize,
/// metadata toggles and DPI on one side; on Process, runs the full
/// decode→resize→encode→embed→verify pipeline and shows a real
/// before/after result, never a hardcoded percentage.
class ProcessingScreen extends StatefulWidget {
  final String assetId;
  const ProcessingScreen({super.key, required this.assetId});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  ImageAsset? _source;
  ProcessingOptions _options = const ProcessingOptions();
  ProcessingResult? _result;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final all = await services.storage.listImages();
    setState(() => _source = all.firstWhere((a) => a.id == widget.assetId));
  }

  Future<void> _process() async {
    final source = _source;
    if (source == null) return;
    setState(() { _processing = true; _error = null; _result = null; });
    try {
      final bytes = await File(source.filePath).readAsBytes();
      final original = MetadataService.inspect(bytes);
      final captureMeta = CaptureMetadata(
        latitude: original.gps?.latitude,
        longitude: original.gps?.longitude,
        altitudeMeters: original.gps?.altitudeMeters,
        gpsAccuracyMeters: original.gps?.accuracyMeters,
        captureTime: original.capturedAt ?? source.createdAt,
        utcOffset: DateTime.now().timeZoneOffset,
        cameraMake: original.camera?.make,
        cameraModel: original.camera?.model,
        exposureTimeSeconds: original.camera?.exposureTimeSeconds,
        fNumber: original.camera?.fNumber,
        iso: original.camera?.iso,
        focalLengthMm: original.camera?.focalLengthMm,
        orientation: original.orientation?.value ?? 1,
        width: original.width,
        height: original.height,
        dpi: _options.dpi,
      );
      final result = await ImageProcessor.process(originalBytes: bytes, options: _options, captureMeta: captureMeta);
      setState(() { _result = result; _processing = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _processing = false; });
    }
  }

  Future<void> _saveResult() async {
    final services = context.read<AppServices>();
    final result = _result;
    final source = _source;
    if (result == null || source == null) return;
    final asset = await services.storage.saveNewImage(
      result.outputBytes,
      format: result.outputFormat,
      width: result.outputWidth,
      height: result.outputHeight,
      isProcessedVariant: true,
      sourceAssetId: source.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved as ${asset.fileName}')));
    }
  }

  Future<void> _uploadResult(UploadMethod method) async {
    final services = context.read<AppServices>();
    final result = _result;
    final source = _source;
    if (result == null || source == null) return;
    final asset = await services.storage.saveNewImage(
      result.outputBytes,
      format: result.outputFormat,
      width: result.outputWidth,
      height: result.outputHeight,
      isProcessedVariant: true,
      sourceAssetId: source.id,
    );
    await services.uploadQueue.enqueue(asset: asset, method: method);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Queued for upload')));
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: const Text('Process Image')),
      body: source == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _formatSection(),
                if (_options.format != ImageFormat.png && !(_options.format == ImageFormat.webp && _options.webpLossless))
                  _qualitySection(),
                _resizeSection(),
                _metadataSection(),
                _dpiSection(),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _processing ? null : _process,
                  icon: _processing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
                  label: const Text('Process Image'),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                if (_result != null) _resultSection(_result!),
              ],
            ),
    );
  }

  Widget _formatSection() {
    return _Section(title: 'Format', child: Wrap(spacing: 8, children: [
      ChoiceChip(label: const Text('JPEG'), selected: _options.format == ImageFormat.jpeg, onSelected: (_) => setState(() => _options = _options.copyWith(format: ImageFormat.jpeg))),
      ChoiceChip(label: const Text('PNG'), selected: _options.format == ImageFormat.png, onSelected: (_) => setState(() => _options = _options.copyWith(format: ImageFormat.png))),
      ChoiceChip(label: const Text('WebP Lossy'), selected: _options.format == ImageFormat.webp && !_options.webpLossless, onSelected: (_) => setState(() => _options = _options.copyWith(format: ImageFormat.webp, webpLossless: false))),
      ChoiceChip(label: const Text('WebP Lossless'), selected: _options.format == ImageFormat.webp && _options.webpLossless, onSelected: (_) => setState(() => _options = _options.copyWith(format: ImageFormat.webp, webpLossless: true))),
    ]));
  }

  Widget _qualitySection() {
    return _Section(
      title: 'Quality: ${_options.quality}',
      child: Slider(value: _options.quality.toDouble(), min: 10, max: 100, divisions: 18, label: '${_options.quality}', onChanged: (v) => setState(() => _options = _options.copyWith(quality: v.round()))),
    );
  }

  Widget _resizeSection() {
    return _Section(
      title: 'Resize (longest side)',
      child: Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('Original'), selected: _options.maxDimension == null, onSelected: (_) => setState(() => _options = _options.copyWith(clearMaxDimension: true))),
        for (final d in ProcessingOptions.resizeOptions)
          ChoiceChip(label: Text('$d'), selected: _options.maxDimension == d, onSelected: (_) => setState(() => _options = _options.copyWith(maxDimension: d))),
      ]),
    );
  }

  Widget _metadataSection() {
    return _Section(title: 'Metadata', child: Column(children: [
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Preserve metadata'), value: _options.preserveMetadata, onChanged: (v) => setState(() => _options = _options.copyWith(preserveMetadata: v))),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('GPS'), value: _options.includeGps, onChanged: _options.preserveMetadata ? (v) => setState(() => _options = _options.copyWith(includeGps: v)) : null),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Capture time'), value: _options.includeCaptureTime, onChanged: _options.preserveMetadata ? (v) => setState(() => _options = _options.copyWith(includeCaptureTime: v)) : null),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Camera information'), value: _options.includeCameraInfo, onChanged: _options.preserveMetadata ? (v) => setState(() => _options = _options.copyWith(includeCameraInfo: v)) : null),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Orientation'), value: _options.includeOrientation, onChanged: _options.preserveMetadata ? (v) => setState(() => _options = _options.copyWith(includeOrientation: v)) : null),
    ]));
  }

  Widget _dpiSection() {
    return _Section(
      title: 'DPI',
      child: Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('None'), selected: _options.dpi == null, onSelected: (_) => setState(() => _options = _options.copyWith(clearDpi: true))),
        for (final d in ProcessingOptions.dpiOptions)
          ChoiceChip(label: Text('$d'), selected: _options.dpi == d, onSelected: (_) => setState(() => _options = _options.copyWith(dpi: d))),
      ]),
    );
  }

  Widget _resultSection(ProcessingResult result) {
    final reduction = result.originalMetadata.fileSizeBytes == 0
        ? 0.0
        : (1 - result.outputBytes.length / result.originalMetadata.fileSizeBytes) * 100;
    return _Section(
      title: 'Result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Original: ${result.originalMetadata.width}×${result.originalMetadata.height} · ${formatBytes(result.originalMetadata.fileSizeBytes)}'),
          Text('Processed: ${result.outputWidth}×${result.outputHeight} · ${formatBytes(result.outputBytes.length)}'),
          Text('Reduction: ${formatPercent(reduction)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Processing time: ${formatMs(result.totalMs)}'),
          const Divider(height: 24),
          Text('Metadata verification', style: Theme.of(context).textTheme.titleSmall),
          ...result.verification.fields.map((f) => FieldComparisonRow(field: f)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saveResult, child: const Text('Save'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () => _uploadResult(UploadMethod.multipart), child: const Text('Upload'))),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}
