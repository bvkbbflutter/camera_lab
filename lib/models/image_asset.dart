import '../services/metadata/image_format.dart';
import '../services/metadata/metadata_models.dart';

/// One image sitting in local app storage: the Gallery's grid items and
/// the Preview screen's subject are both backed by this. Metadata is
/// re-read from the file on demand (via [MetadataService.inspect]) rather
/// than cached separately as a JSON sidecar — the file remains the single
/// source of truth (spec §17: "Do not read it from a separately stored
/// metadata JSON object").
class ImageAsset {
  final String id;
  final String filePath;
  final ImageFormat format;
  final int width;
  final int height;
  final int fileSizeBytes;
  final DateTime createdAt;
  final bool isProcessedVariant;
  final String? sourceAssetId; // links a processed output back to its original capture

  const ImageAsset({
    required this.id,
    required this.filePath,
    required this.format,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.createdAt,
    this.isProcessedVariant = false,
    this.sourceAssetId,
  });

  String get fileName => filePath.split('/').last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'format': format.name,
        'width': width,
        'height': height,
        'fileSizeBytes': fileSizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'isProcessedVariant': isProcessedVariant,
        'sourceAssetId': sourceAssetId,
      };

  factory ImageAsset.fromJson(Map<String, dynamic> json) => ImageAsset(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        format: ImageFormat.values.byName(json['format'] as String),
        width: json['width'] as int,
        height: json['height'] as int,
        fileSizeBytes: json['fileSizeBytes'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isProcessedVariant: json['isProcessedVariant'] as bool? ?? false,
        sourceAssetId: json['sourceAssetId'] as String?,
      );
}

/// A cached inspection result paired with the asset it describes, used so
/// screens don't need to re-read+re-parse the file on every rebuild.
class InspectedAsset {
  final ImageAsset asset;
  final ImageMetadataReport metadata;
  const InspectedAsset({required this.asset, required this.metadata});
}
