import 'settings_service.dart';
import '../services/camera/camera_service.dart';
import '../services/camera/device_info_service.dart';
import '../services/storage/local_storage_service.dart';
import '../services/upload/upload_service.dart';
import '../services/upload/upload_queue.dart';

/// Wires up every service once at app start. Passed down via `provider`
/// (see main.dart) rather than re-instantiated per screen.
class AppServices {
  final SettingsService settings;
  final LocalStorageService storage;
  final DeviceInfoService deviceInfo;
  final CameraService camera;
  final UploadService uploadService;
  final UploadQueue uploadQueue;

  AppServices._({
    required this.settings,
    required this.storage,
    required this.deviceInfo,
    required this.camera,
    required this.uploadService,
    required this.uploadQueue,
  });

  static Future<AppServices> bootstrap() async {
    final settings = await SettingsService.instance();
    final storage = LocalStorageService();
    await storage.init();
    final uploadService = UploadService(settings);
    final uploadQueue = UploadQueue(storage: storage, uploadService: uploadService, settings: settings);
    await uploadQueue.load();

    return AppServices._(
      settings: settings,
      storage: storage,
      deviceInfo: DeviceInfoService(),
      camera: CameraService(),
      uploadService: uploadService,
      uploadQueue: uploadQueue,
    );
  }
}
