/// Spec §36: the offline upload queue's state machine.
enum UploadStatus { pending, processing, uploading, success, failed, retry }

enum UploadMethod { base64, multipart }

class UploadTask {
  final String id;
  final String imageAssetId;
  final String filePath;
  final UploadMethod method;
  UploadStatus status;
  int attempts;
  String? lastError;
  DateTime createdAt;
  DateTime? lastAttemptAt;
  String? remoteFileId;

  UploadTask({
    required this.id,
    required this.imageAssetId,
    required this.filePath,
    required this.method,
    this.status = UploadStatus.pending,
    this.attempts = 0,
    this.lastError,
    DateTime? createdAt,
    this.lastAttemptAt,
    this.remoteFileId,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageAssetId': imageAssetId,
        'filePath': filePath,
        'method': method.name,
        'status': status.name,
        'attempts': attempts,
        'lastError': lastError,
        'createdAt': createdAt.toIso8601String(),
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'remoteFileId': remoteFileId,
      };

  factory UploadTask.fromJson(Map<String, dynamic> json) => UploadTask(
        id: json['id'] as String,
        imageAssetId: json['imageAssetId'] as String,
        filePath: json['filePath'] as String,
        method: UploadMethod.values.byName(json['method'] as String),
        status: UploadStatus.values.byName(json['status'] as String),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['lastError'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastAttemptAt: json['lastAttemptAt'] == null ? null : DateTime.parse(json['lastAttemptAt'] as String),
        remoteFileId: json['remoteFileId'] as String?,
      );
}
