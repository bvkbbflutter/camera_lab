import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Spec §8: "Where the camera API exposes it... Device manufacturer,
/// Device model... Do not fabricate values if the OS does not expose them."
class DeviceCameraInfo {
  final String? make;
  final String? model;
  const DeviceCameraInfo({this.make, this.model});
}

class DeviceInfoService {
  DeviceCameraInfo? _cached;

  Future<DeviceCameraInfo> get() async {
    if (_cached != null) return _cached!;
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _cached = DeviceCameraInfo(make: _capitalize(info.manufacturer), model: info.model);
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _cached = DeviceCameraInfo(make: 'Apple', model: info.utsname.machine); // e.g. "iPhone15,3"
      } else {
        _cached = const DeviceCameraInfo();
      }
    } catch (_) {
      _cached = const DeviceCameraInfo();
    }
    return _cached!;
  }

  static String? _capitalize(String? s) {
    if (s == null || s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
