import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../core/format_utils.dart';
import '../../models/benchmark_result.dart';
import '../../models/image_asset.dart';
import '../../services/benchmark/benchmark_export.dart';
import '../../services/benchmark/benchmark_service.dart';
import '../../services/metadata/exif_builder.dart';
import '../../services/metadata/metadata_service.dart';

/// Spec §52/§53: "Run Full Benchmark" — sweeps the fixed format/quality
/// matrix against a chosen source image and exports results as CSV/JSON.
class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  List<ImageAsset> _assets = [];
  String? _selectedAssetId;
  bool _running = false;
  String _progressLabel = '';
  double _progress = 0;
  bool _alsoUpload = false;
  BenchmarkRun? _run;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final services = context.read<AppServices>();
    final all = await services.storage.listImages();
    setState(() {
      _assets = all;
      _selectedAssetId ??= all.isNotEmpty ? all.first.id : null;
    });
  }

  Future<void> _run_() async {
    final services = context.read<AppServices>();
    final assetId = _selectedAssetId;
    if (assetId == null || _running) return;
    final asset = _assets.firstWhere((a) => a.id == assetId);
    setState(() { _running = true; _progress = 0; _run = null; });

    final captureSw = Stopwatch()..start();
    final bytes = await File(asset.filePath).readAsBytes();
    captureSw.stop();

    final original = MetadataService.inspect(bytes);
    final captureMeta = CaptureMetadata(
      latitude: original.gps?.latitude,
      longitude: original.gps?.longitude,
      captureTime: original.capturedAt ?? asset.createdAt,
      utcOffset: DateTime.now().timeZoneOffset,
      cameraMake: original.camera?.make,
      cameraModel: original.camera?.model,
      lensFacing: null,
      orientation: original.orientation?.value ?? 1,
      width: original.width,
      height: original.height,
      dpi: original.dpi?.x.round() ?? 300,
    );

    final benchmark = BenchmarkService(uploadService: _alsoUpload ? services.uploadService : null);
    final run = await benchmark.run(
      sourceBytes: bytes,
      captureMeta: captureMeta,
      captureTimeMs: captureSw.elapsedMilliseconds,
      alsoUpload: _alsoUpload,
      onProgress: (completed, total, label) {
        if (mounted) setState(() { _progress = total == 0 ? 0 : completed / total; _progressLabel = label; });
      },
    );

    if (mounted) setState(() { _run = run; _running = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Source image'),
            value: _selectedAssetId,
            items: [for (final a in _assets) DropdownMenuItem(value: a.id, child: Text('${a.fileName} (${a.width}×${a.height})'))],
            onChanged: (v) => setState(() => _selectedAssetId = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also measure Base64 vs multipart upload'),
            subtitle: const Text('Requires the server to be reachable'),
            value: _alsoUpload,
            onChanged: (v) => setState(() => _alsoUpload = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (_selectedAssetId == null || _running) ? null : _run_,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Full Benchmark'),
          ),
          if (_running) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(children: [LinearProgressIndicator(value: _progress), const SizedBox(height: 4), Text(_progressLabel)]),
          ),
          if (_run != null) ..._resultsSection(_run!),
        ],
      ),
    );
  }

  List<Widget> _resultsSection(BenchmarkRun run) {
    return [
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text('${run.results.length} variants · ${run.device}', style: Theme.of(context).textTheme.titleSmall)),
        IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Export CSV', onPressed: () => BenchmarkExport.shareCsv(run)),
        IconButton(icon: const Icon(Icons.data_object), tooltip: 'Export JSON', onPressed: () => BenchmarkExport.shareJson(run)),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Format')),
            DataColumn(label: Text('Size')),
            DataColumn(label: Text('Reduction')),
            DataColumn(label: Text('Encode')),
            DataColumn(label: Text('Meta write')),
            DataColumn(label: Text('Base64')),
            DataColumn(label: Text('Multipart↑')),
            DataColumn(label: Text('Base64↑')),
            DataColumn(label: Text('Meta OK')),
          ],
          rows: [
            for (final r in run.results)
              DataRow(cells: [
                DataCell(Text('${r.format} ${r.quality}')),
                DataCell(Text(formatBytes(r.processedSizeBytes))),
                DataCell(Text(formatPercent(r.reductionPercent))),
                DataCell(Text(formatMs(r.encodeTimeMs))),
                DataCell(Text(formatMs(r.metadataWriteTimeMs))),
                DataCell(Text(formatBytes(r.base64SizeBytes))),
                DataCell(Text(r.multipartUploadMs != null ? formatMs(r.multipartUploadMs!) : '—')),
                DataCell(Text(r.base64UploadMs != null ? formatMs(r.base64UploadMs!) : '—')),
                DataCell(Icon(r.metadataPreserved ? Icons.check : Icons.close, color: r.metadataPreserved ? Colors.green : Colors.red, size: 18)),
              ]),
          ],
        ),
      ),
    ];
  }
}
