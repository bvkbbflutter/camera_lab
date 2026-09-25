import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_services.dart';
import '../../core/format_utils.dart';
import '../../models/image_asset.dart';
import '../../models/processing_options.dart';
import '../../services/image_processing/image_processor.dart';
import '../../services/metadata/exif_builder.dart';
import '../../services/metadata/image_format.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/metadata/metadata_models.dart';

class _Variant {
  final String label;
  final ImageFormat format;
  final int quality;
  final bool lossless;
  const _Variant(this.label, this.format, this.quality, {this.lossless = false});
}

const List<_Variant> _variants = [
  _Variant('JPEG 60', ImageFormat.jpeg, 60),
  _Variant('JPEG 75', ImageFormat.jpeg, 75),
  _Variant('JPEG 80', ImageFormat.jpeg, 80),
  _Variant('JPEG 85', ImageFormat.jpeg, 85),
  _Variant('JPEG 90', ImageFormat.jpeg, 90),
  _Variant('JPEG 95', ImageFormat.jpeg, 95),
  _Variant('JPEG 100', ImageFormat.jpeg, 100),
  _Variant('PNG', ImageFormat.png, 100),
  _Variant('WebP 60', ImageFormat.webp, 60),
  _Variant('WebP 75', ImageFormat.webp, 75),
  _Variant('WebP 80', ImageFormat.webp, 80),
  _Variant('WebP 85', ImageFormat.webp, 85),
  _Variant('WebP 90', ImageFormat.webp, 90),
  _Variant('WebP 95', ImageFormat.webp, 95),
  _Variant('WebP Lossless', ImageFormat.webp, 100, lossless: true),
];

class ComparisonScreen extends StatefulWidget {
  final String assetId;
  const ComparisonScreen({super.key, required this.assetId});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  ImageAsset? _source;
  Uint8List? _sourceBytes;
  final Map<String, ProcessingResult> _results = {};
  bool _running = false;
  
  final List<_Variant> _activeVariants = List.from(_variants);
  ImageFormat _customFormat = ImageFormat.jpeg;
  double _customQuality = 80;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final all = await services.storage.listImages();
    final asset = all.firstWhere((a) => a.id == widget.assetId);
    final bytes = await File(asset.filePath).readAsBytes();
    setState(() { _source = asset; _sourceBytes = bytes; });
  }

  CaptureMetadata _getCaptureMeta() {
    final original = MetadataService.inspect(_sourceBytes!);
    return CaptureMetadata(
      latitude: original.gps?.latitude,
      longitude: original.gps?.longitude,
      captureTime: original.capturedAt ?? DateTime.now(),
      utcOffset: DateTime.now().timeZoneOffset,
      cameraMake: original.camera?.make,
      cameraModel: original.camera?.model,
      orientation: original.orientation?.value ?? 1,
      width: original.width,
      height: original.height,
      dpi: original.dpi?.x.round(),
    );
  }

  Future<void> _runAll() async {
    if (_sourceBytes == null || _running) return;
    setState(() => _running = true);
    final captureMeta = _getCaptureMeta();

    for (final v in _activeVariants) {
      final options = _optionsFor(v);
      try {
        final result = await ImageProcessor.process(originalBytes: _sourceBytes!, options: options, captureMeta: captureMeta);
        _results[v.label] = result;
      } catch (_) {
      }
      if (mounted) setState(() {});
    }
    setState(() => _running = false);
  }

  Future<void> _runSingle(_Variant v) async {
    if (_sourceBytes == null || _running) return;
    setState(() => _running = true);
    final captureMeta = _getCaptureMeta();
    final options = _optionsFor(v);
    try {
      final result = await ImageProcessor.process(originalBytes: _sourceBytes!, options: options, captureMeta: captureMeta);
      _results[v.label] = result;
    } catch (_) {}
    if (mounted) setState(() => _running = false);
  }

  ProcessingOptions _optionsFor(_Variant v) {
    return ProcessingOptions(
      format: v.format,
      webpLossless: v.lossless,
      quality: v.quality,
      maxDimension: null,
      preserveMetadata: true,
      includeGps: true,
      dpi: 300,
    );
  }

  Future<void> _previewCustom() async {
    if (_sourceBytes == null || _running) return;
    setState(() => _running = true);
    final variant = _Variant('Preview ${_customFormat.name} ${_customQuality.toInt()}', _customFormat, _customQuality.toInt());
    final options = _optionsFor(variant);
    try {
      final result = await ImageProcessor.process(originalBytes: _sourceBytes!, options: options, captureMeta: _getCaptureMeta());
      if (mounted) _showPreviewDialog(context, variant.label, result.outputBytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _addCustomVariant() async {
    final variant = _Variant('Custom ${_customFormat.name} ${_customQuality.toInt()}', _customFormat, _customQuality.toInt());
    setState(() => _activeVariants.add(variant));
    _runSingle(variant);
  }

  Future<void> _shareVariant(String label, ProcessingResult result) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$label.${result.outputFormat.extension}');
    await file.writeAsBytes(result.outputBytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Check out this $label image!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Format & Quality Comparison'), actions: [
        IconButton(icon: const Icon(Icons.play_arrow), onPressed: _running ? null : _runAll, tooltip: 'Run all variants'),
      ]),
      body: _source == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_running) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Table(
                      columnWidths: const {0: FlexColumnWidth(1.4), 4: IntrinsicColumnWidth()},
                      children: [
                        const TableRow(children: [
                          Padding(padding: EdgeInsets.all(4), child: Text('Variant', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(4), child: Text('Size', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(4), child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(4), child: Text('Meta', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(4), child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                        ]),
                        if (_sourceBytes != null)
                          TableRow(
                            decoration: const BoxDecoration(color: Colors.black12),
                            children: [
                              const Padding(padding: EdgeInsets.all(4), child: Text('Original', style: TextStyle(fontWeight: FontWeight.bold))),
                              Padding(padding: const EdgeInsets.all(4), child: Text(formatBytes(_sourceBytes!.length))),
                              const Padding(padding: EdgeInsets.all(4), child: Text('—')),
                              const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle, size: 16, color: Colors.green)),
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.share, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        await Share.shareXFiles([XFile(_source!.filePath)], text: 'Check out the Original image!');
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.image, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _showPreviewDialog(context, 'Original', _sourceBytes!),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        for (final v in _activeVariants)
                          TableRow(children: [
                            Padding(padding: const EdgeInsets.all(4), child: Text(v.label)),
                            Padding(padding: const EdgeInsets.all(4), child: Text(_results[v.label] != null ? formatBytes(_results[v.label]!.outputBytes.length) : '—')),
                            Padding(padding: const EdgeInsets.all(4), child: Text(_results[v.label] != null ? formatMs(_results[v.label]!.totalMs) : '—')),
                            Padding(padding: const EdgeInsets.all(4), child: _results[v.label] == null ? const SizedBox() : IconButton(
                              icon: Icon(
                                _results[v.label]!.verification.allExpectedFieldsPreserved ? Icons.check_circle : Icons.info,
                                color: _results[v.label]!.verification.allExpectedFieldsPreserved ? Colors.green : Colors.orange,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showMetadataDialog(context, v.label, _results[v.label]!.verification),
                            )),
                            Padding(padding: const EdgeInsets.all(4), child: _results[v.label] == null ? const SizedBox() : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.share, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _shareVariant(v.label, _results[v.label]!),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.image, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _showPreviewDialog(context, v.label, _results[v.label]!.outputBytes);
                                  },
                                ),
                              ],
                            )),
                          ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                Text('Custom Creation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ImageFormat>(
                        value: _customFormat,
                        items: ImageFormat.values.map((f) => DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))).toList(),
                        onChanged: (v) { if (v != null) setState(() => _customFormat = v); },
                        decoration: const InputDecoration(labelText: 'Format', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _customQuality.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quality (0-100)', border: OutlineInputBorder()),
                        onChanged: (v) => _customQuality = double.tryParse(v) ?? _customQuality,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _running ? null : _previewCustom,
                      child: const Text('Preview'),
                    ),
                    ElevatedButton(
                      onPressed: _running ? null : _addCustomVariant,
                      child: const Text('Add to list'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  void _showMetadataDialog(BuildContext context, String title, MetadataVerificationResult verification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title Metadata'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: verification.fields.map((f) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      f.status == FieldStatus.preserved ? Icons.check_circle : (f.status == FieldStatus.changed ? Icons.info : Icons.warning),
                      size: 16,
                      color: f.status == FieldStatus.preserved ? Colors.green : (f.status == FieldStatus.changed ? Colors.blue : Colors.orange),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Expected: ${f.originalValue ?? 'None'}', style: const TextStyle(fontSize: 12)),
                          Text('Actual: ${f.outputValue ?? 'None'}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showPreviewDialog(BuildContext context, String title, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Column(
          children: [
            AppBar(
              title: Text(title),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
