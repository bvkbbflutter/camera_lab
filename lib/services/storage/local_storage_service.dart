import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/image_asset.dart';
import '../../models/upload_task.dart';
import '../metadata/image_format.dart';

const _uuid = Uuid();

/// Spec §36: "Store the processed image locally until upload succeeds. Do
/// not delete the only copy before the server confirms success." All
/// captured/processed images and the upload queue index live in the app's
/// documents directory, independent of any server round-trip.
class LocalStorageService {
  late final Directory _imagesDir;
  late final File _assetsIndexFile;
  late final File _queueIndexFile;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _imagesDir = Directory('${docs.path}/camera_lab_images');
    if (!await _imagesDir.exists()) await _imagesDir.create(recursive: true);
    _assetsIndexFile = File('${docs.path}/camera_lab_assets.json');
    _queueIndexFile = File('${docs.path}/camera_lab_queue.json');
  }

  String get imagesDirPath => _imagesDir.path;

  // ---- images ---------------------------------------------------------

  Future<ImageAsset> saveNewImage(
    Uint8List bytes, {
    required ImageFormat format,
    required int width,
    required int height,
    bool isProcessedVariant = false,
    String? sourceAssetId,
  }) async {
    final id = _uuid.v4();
    final fileName = '$id.${format.extension}';
    final file = File('${_imagesDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final asset = ImageAsset(
      id: id,
      filePath: file.path,
      format: format,
      width: width,
      height: height,
      fileSizeBytes: bytes.length,
      createdAt: DateTime.now(),
      isProcessedVariant: isProcessedVariant,
      sourceAssetId: sourceAssetId,
    );
    final all = await listImages();
    all.insert(0, asset);
    await _writeAssetsIndex(all);
    return asset;
  }

  Future<List<ImageAsset>> listImages() async {
    if (!await _assetsIndexFile.exists()) return [];
    try {
      final raw = await _assetsIndexFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => ImageAsset.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteImage(String id) async {
    final all = await listImages();
    final idx = all.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final asset = all[idx];
    final file = File(asset.filePath);
    if (await file.exists()) await file.delete();
    all.removeAt(idx);
    await _writeAssetsIndex(all);
  }

  Future<void> deleteAllImages() async {
    final all = await listImages();
    for (final asset in all) {
      final file = File(asset.filePath);
      if (await file.exists()) await file.delete();
    }
    await _writeAssetsIndex([]);
  }

  Future<void> _writeAssetsIndex(List<ImageAsset> assets) async {
    await _assetsIndexFile.writeAsString(jsonEncode(assets.map((a) => a.toJson()).toList()));
  }

  // ---- upload queue -----------------------------------------------------

  Future<List<UploadTask>> listQueue() async {
    if (!await _queueIndexFile.exists()) return [];
    try {
      final raw = await _queueIndexFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => UploadTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQueue(List<UploadTask> tasks) async {
    await _queueIndexFile.writeAsString(jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();
}
