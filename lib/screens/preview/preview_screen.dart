import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../models/image_asset.dart';
import '../../models/upload_task.dart';
import '../../services/metadata/image_format.dart';
import '../comparison/comparison_screen.dart';
import '../details/image_details_screen.dart';
import '../processing/processing_screen.dart';

/// Spec §16: the post-capture preview with a "⋮" menu offering View
/// Details / Process Image / Upload / Save / Delete.
class PreviewScreen extends StatefulWidget {
  final String assetId;
  final bool fromCapture;
  const PreviewScreen({super.key, required this.assetId, this.fromCapture = false});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  ImageAsset? _asset;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final all = await services.storage.listImages();
    setState(() => _asset = all.firstWhere((a) => a.id == widget.assetId));
  }

  Future<void> _upload(UploadMethod method) async {
    final services = context.read<AppServices>();
    if (_asset == null) return;
    await services.uploadQueue.enqueue(asset: _asset!, method: method);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued for ${method == UploadMethod.base64 ? 'Base64' : 'multipart'} upload')),
      );
    }
  }

  Future<void> _delete() async {
    final services = context.read<AppServices>();
    if (_asset == null) return;
    await services.storage.deleteImage(_asset!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: widget.fromCapture ? null : [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (asset == null) return;
              switch (value) {
                case 'details':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageDetailsScreen(assetId: asset.id)));
                  break;
                case 'process':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProcessingScreen(assetId: asset.id)));
                  break;
                case 'compare':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComparisonScreen(assetId: asset.id)));
                  break;
                case 'upload_base64':
                  _upload(UploadMethod.base64);
                  break;
                case 'upload_multipart':
                  _upload(UploadMethod.multipart);
                  break;
                case 'delete':
                  _delete();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'details', child: Text('View Details')),
              PopupMenuItem(value: 'process', child: Text('Process Image')),
              PopupMenuItem(value: 'compare', child: Text('Compare Formats')),
              PopupMenuItem(value: 'upload_base64', child: Text('Upload (Base64 JSON)')),
              PopupMenuItem(value: 'upload_multipart', child: Text('Upload (Multipart)')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: asset == null
          ? const Center(child: CircularProgressIndicator())
          : Center(child: InteractiveViewer(child: Image.file(File(asset.filePath)))),
      bottomNavigationBar: asset == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: widget.fromCapture
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${asset.format.label} · ${asset.width}×${asset.height} · ${_sizeLabel(asset.fileSizeBytes)}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton(
                                onPressed: _delete,
                                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                              ),
                              ElevatedButton(
                                onPressed: _delete,
                                child: const Text('Retake'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Text(
                        '${asset.format.label} · ${asset.width}×${asset.height} · ${_sizeLabel(asset.fileSizeBytes)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            ),
    );
  }

  String _sizeLabel(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
