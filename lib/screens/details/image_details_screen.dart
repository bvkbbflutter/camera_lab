import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../core/format_utils.dart';
import '../../models/image_asset.dart';
import '../../services/metadata/image_format.dart';
import '../../services/metadata/metadata_models.dart';
import '../../services/metadata/metadata_service.dart';
import '../../widgets/metadata_tile.dart';

/// Spec §15/§45: the dedicated "Image Details" metadata inspector —
/// EVERYTHING here is read live from the image file's own embedded
/// metadata, never from a separate JSON store.
class ImageDetailsScreen extends StatefulWidget {
  final String assetId;
  const ImageDetailsScreen({super.key, required this.assetId});

  @override
  State<ImageDetailsScreen> createState() => _ImageDetailsScreenState();
}

class _ImageDetailsScreenState extends State<ImageDetailsScreen> {
  ImageAsset? _asset;
  ImageMetadataReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final all = await services.storage.listImages();
    final asset = all.firstWhere((a) => a.id == widget.assetId);
    try {
      final bytes = await File(asset.filePath).readAsBytes();
      final report = MetadataService.inspect(bytes);
      setState(() { _asset = asset; _report = report; });
    } catch (e) {
      setState(() { _asset = asset; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Image Details')),
      body: asset == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not read metadata: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const MetadataSectionHeader(title: 'File'),
                    MetadataTile(label: 'Name', value: asset.fileName),
                    MetadataTile(label: 'Format', value: asset.format.label),
                    MetadataTile(label: 'Size', value: formatBytes(asset.fileSizeBytes)),

                    const MetadataSectionHeader(title: 'Dimensions'),
                    MetadataTile(label: 'Width', value: '${report?.width ?? asset.width} px'),
                    MetadataTile(label: 'Height', value: '${report?.height ?? asset.height} px'),
                    MetadataTile(label: 'Resolution', value: '${report?.width ?? asset.width} × ${report?.height ?? asset.height}'),

                    const MetadataSectionHeader(title: 'Camera'),
                    MetadataTile(label: 'Make', value: report?.camera?.make),
                    MetadataTile(label: 'Model', value: report?.camera?.model),
                    MetadataTile(label: 'Lens', value: report?.camera?.lensModel),
                    MetadataTile(label: 'Exposure', value: report?.camera?.exposureTimeSeconds != null ? '1/${(1 / report!.camera!.exposureTimeSeconds!).round()}s' : null),
                    MetadataTile(label: 'F-Number', value: report?.camera?.fNumber != null ? 'f/${report!.camera!.fNumber!.toStringAsFixed(1)}' : null),
                    MetadataTile(label: 'ISO', value: report?.camera?.iso?.toString()),

                    const MetadataSectionHeader(title: 'Capture'),
                    MetadataTile(label: 'Date', value: report?.capturedAt != null ? formatDate(report!.capturedAt!) : null),
                    MetadataTile(label: 'Time', value: report?.capturedAt != null ? formatTime(report!.capturedAt!) : null),

                    const MetadataSectionHeader(title: 'Location'),
                    MetadataTile(label: 'Latitude', value: report?.gps?.latitude.toStringAsFixed(6)),
                    MetadataTile(label: 'Longitude', value: report?.gps?.longitude.toStringAsFixed(6)),
                    MetadataTile(label: 'Altitude', value: report?.gps?.altitudeMeters != null ? '${report!.gps!.altitudeMeters!.toStringAsFixed(0)} m' : null),
                    MetadataTile(label: 'Accuracy', value: report?.gps?.accuracyMeters != null ? '±${report!.gps!.accuracyMeters!.toStringAsFixed(0)} m' : null),

                    const MetadataSectionHeader(title: 'Image'),
                    MetadataTile(label: 'Orientation', value: report?.orientation?.label),
                    MetadataTile(label: 'DPI', value: report?.dpi != null ? '${report!.dpi!.x.round()} (${report.dpi!.source})' : null),
                    if (asset.format.name == 'webp') MetadataTile(label: 'WebP encoding', value: report?.webpEncoding),

                    const MetadataSectionHeader(title: 'EXIF'),
                    MetadataTile(label: 'Present', value: report?.exifPresent == true ? 'Present' : 'Not present'),
                    MetadataTile(label: 'Metadata size', value: report != null ? formatBytes(report.metadataBytes) : null),
                  ],
                ),
    );
  }
}
