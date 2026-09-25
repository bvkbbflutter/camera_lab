import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../core/format_utils.dart';
import '../../models/image_asset.dart';
import '../../models/upload_task.dart';
import '../../services/metadata/image_format.dart';
import '../details/image_details_screen.dart';
import '../preview/preview_screen.dart';
import '../processing/processing_screen.dart';
import '../camera/camera_screen.dart';

/// Spec §17: in-app gallery grid — thumbnail, format, resolution, file
/// size per card; tap for full-screen preview; menu for Details/Process/
/// Upload/Delete. Metadata is always re-read from the file itself.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<ImageAsset> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final services = context.read<AppServices>();
    final assets = await services.storage.listImages();
    if (mounted) setState(() { _assets = assets; _loading = false; });
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete All'),
        content: const Text('Are you sure you want to delete all images?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final services = context.read<AppServices>();
    await services.storage.deleteAllImages();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gallery'), actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Delete All',
          onPressed: _assets.isEmpty ? null : _deleteAll,
        ),
        IconButton(
          icon: const Icon(Icons.camera_alt),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Select Resolution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    for (final preset in ResolutionPreset.values)
                      ListTile(
                        title: Text(preset.name.toUpperCase()),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CameraScreen(preset: preset)));
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
      ]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _assets.isEmpty
                ? ListView(children: const [
                    Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No captures yet. Take a photo to get started.'))),
                  ])
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.8),
                    itemCount: _assets.length,
                    itemBuilder: (context, i) => _GalleryCard(asset: _assets[i], onChanged: _refresh),
                  ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final ImageAsset asset;
  final VoidCallback onChanged;
  const _GalleryCard({required this.asset, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PreviewScreen(assetId: asset.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Image.file(File(asset.filePath), fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${asset.format.label} · ${asset.width}×${asset.height}', style: Theme.of(context).textTheme.labelSmall),
                        Text(formatBytes(asset.fileSizeBytes), style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (v) async {
                      final services = context.read<AppServices>();
                      switch (v) {
                        case 'details':
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageDetailsScreen(assetId: asset.id)));
                          break;
                        case 'process':
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProcessingScreen(assetId: asset.id)));
                          break;
                        case 'upload':
                          await services.uploadQueue.enqueue(asset: asset, method: UploadMethod.multipart);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Queued for upload')));
                          }
                          break;
                        case 'delete':
                          await services.storage.deleteImage(asset.id);
                          onChanged();
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'details', child: Text('Image Details')),
                      PopupMenuItem(value: 'process', child: Text('Process')),
                      PopupMenuItem(value: 'upload', child: Text('Upload')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
