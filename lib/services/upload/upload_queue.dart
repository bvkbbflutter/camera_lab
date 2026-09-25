import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/settings_service.dart';
import '../../models/image_asset.dart';
import '../../models/upload_task.dart';
import '../metadata/image_format.dart';
import '../storage/local_storage_service.dart';
import 'upload_service.dart';

const _uuid = Uuid();

/// Spec §36/§37: persistent, retryable upload queue. Every state change is
/// written back to disk immediately, so the queue survives app restarts —
/// this is what makes "offline capture, upload later" actually work.
class UploadQueue extends ChangeNotifier {
  final LocalStorageService storage;
  final UploadService uploadService;
  final SettingsService settings;

  UploadQueue({required this.storage, required this.uploadService, required this.settings});

  List<UploadTask> _tasks = [];
  List<UploadTask> get tasks => List.unmodifiable(_tasks);
  bool _draining = false;

  Future<void> load() async {
    _tasks = await storage.listQueue();
    notifyListeners();
  }

  Future<UploadTask> enqueue({
    required ImageAsset asset,
    required UploadMethod method,
  }) async {
    final task = UploadTask(id: _uuid.v4(), imageAssetId: asset.id, filePath: asset.filePath, method: method);
    _tasks.insert(0, task);
    await _persist();
    notifyListeners();
    unawaited(drain());
    return task;
  }

  Future<void> retry(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.status = UploadStatus.pending;
    task.lastError = null;
    await _persist();
    notifyListeners();
    unawaited(drain());
  }

  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    await _persist();
    notifyListeners();
  }

  Future<void> uploadNow(String taskId) => retry(taskId);

  /// Processes every PENDING/RETRY task in order. Safe to call repeatedly;
  /// re-entrant calls are ignored while a drain is already running.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final task in List<UploadTask>.from(_tasks)) {
        if (task.status != UploadStatus.pending && task.status != UploadStatus.retry) continue;
        await _attempt(task);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _attempt(UploadTask task) async {
    task.status = UploadStatus.uploading;
    task.attempts += 1;
    task.lastAttemptAt = DateTime.now();
    notifyListeners();
    await _persist();

    try {
      final bytes = await storage.readBytes(task.filePath);
      final format = task.filePath.endsWith('.png')
          ? ImageFormat.png
          : task.filePath.endsWith('.webp')
              ? ImageFormat.webp
              : ImageFormat.jpeg;
      final fileName = task.filePath.split('/').last;

      final result = task.method == UploadMethod.base64
          ? await uploadService.uploadBase64(imageBytes: bytes, fileName: fileName, format: format, uploadId: task.id)
          : await uploadService.uploadMultipart(imageBytes: bytes, fileName: fileName, format: format, uploadId: task.id);

      if (result.success) {
        task.status = UploadStatus.success;
        task.remoteFileId = result.fileId;
        task.lastError = null;
      } else {
        task.lastError = '${result.errorCode ?? result.statusCode}: ${result.errorMessage ?? 'upload failed'}';
        task.status = task.attempts < settings.maxUploadRetries ? UploadStatus.retry : UploadStatus.failed;
      }
    } catch (e) {
      task.lastError = e.toString();
      task.status = task.attempts < settings.maxUploadRetries ? UploadStatus.retry : UploadStatus.failed;
    }

    await _persist();
    notifyListeners();
  }

  int get pendingCount => _tasks.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.retry).length;
  int get failedCount => _tasks.where((t) => t.status == UploadStatus.failed).length;

  Future<void> _persist() => storage.saveQueue(_tasks);
}
