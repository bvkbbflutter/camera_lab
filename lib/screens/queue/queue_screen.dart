import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/upload_task.dart';
import '../../services/upload/upload_queue.dart';

/// Spec §36/§37: the offline upload queue — every task's state machine
/// (PENDING/PROCESSING/UPLOADING/SUCCESS/FAILED/RETRY) with Retry/Delete/
/// Upload now actions. The image itself is never deleted until the
/// server confirms success.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<UploadQueue>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [IconButton(icon: const Icon(Icons.sync), tooltip: 'Retry all pending', onPressed: queue.drain)],
      ),
      body: queue.tasks.isEmpty
          ? const Center(child: Text('Queue is empty'))
          : ListView.separated(
              itemCount: queue.tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _QueueTile(task: queue.tasks[i]),
            ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final UploadTask task;
  const _QueueTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final queue = context.read<UploadQueue>();
    final (color, icon) = switch (task.status) {
      UploadStatus.pending => (Colors.grey, Icons.schedule),
      UploadStatus.processing => (Colors.blue, Icons.hourglass_top),
      UploadStatus.uploading => (Colors.blue, Icons.cloud_upload),
      UploadStatus.success => (Colors.green, Icons.check_circle),
      UploadStatus.failed => (Colors.red, Icons.error),
      UploadStatus.retry => (Colors.orange, Icons.refresh),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(task.filePath.split('/').last),
      subtitle: Text(
        '${task.method == UploadMethod.base64 ? 'Base64' : 'Multipart'} · '
        '${task.status.name.toUpperCase()} · attempts: ${task.attempts}'
        '${task.lastError != null ? '\n${task.lastError}' : ''}',
      ),
      isThreeLine: task.lastError != null,
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'retry') queue.retry(task.id);
          if (v == 'delete') queue.deleteTask(task.id);
          if (v == 'upload_now') queue.uploadNow(task.id);
        },
        itemBuilder: (_) => [
          if (task.status == UploadStatus.failed || task.status == UploadStatus.retry) const PopupMenuItem(value: 'retry', child: Text('Retry')),
          if (task.status == UploadStatus.pending) const PopupMenuItem(value: 'upload_now', child: Text('Upload now')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
