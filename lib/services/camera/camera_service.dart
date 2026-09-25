import 'package:camera/camera.dart';
import 'package:flutter/material.dart' show ChangeNotifier, Offset;

/// Spec §1/§9: camera capture, resolutions, front/back, flash, focus,
/// exposure, zoom, and correct orientation handling, wrapped around the
/// `camera` plugin so screens don't talk to CameraController directly.
class CameraService extends ChangeNotifier {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  ResolutionPreset _resolutionPreset = ResolutionPreset.max;
  FlashMode _flashMode = FlashMode.auto;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _exposureOffset = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  bool get isFrontFacing => _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  FlashMode get flashMode => _flashMode;
  double get zoom => _zoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get exposureOffset => _exposureOffset;
  double get minExposure => _minExposure;
  double get maxExposure => _maxExposure;
  ResolutionPreset get resolutionPreset => _resolutionPreset;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize({ResolutionPreset? preset}) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('no_cameras', 'No cameras were found on this device');
    }
    if (preset != null) _resolutionPreset = preset;
    await _openController();
  }

  Future<void> _openController() async {
    final old = _controller;
    _controller = CameraController(
      _cameras[_cameraIndex],
      _resolutionPreset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _controller!.initialize();
    _minZoom = await _controller!.getMinZoomLevel();
    _maxZoom = await _controller!.getMaxZoomLevel();
    _zoom = _minZoom;
    _minExposure = await _controller!.getMinExposureOffset();
    _maxExposure = await _controller!.getMaxExposureOffset();
    _exposureOffset = 0.0;
    await _controller!.setFlashMode(_flashMode);
    await old?.dispose();
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _openController();
  }

  Future<void> setResolutionPreset(ResolutionPreset preset) async {
    _resolutionPreset = preset;
    await _openController();
  }

  Future<void> setFlashMode(FlashMode mode) async {
    _flashMode = mode;
    await _controller?.setFlashMode(mode);
    notifyListeners();
  }

  Future<void> setZoom(double value) async {
    final clamped = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller?.setZoomLevel(clamped);
      _zoom = clamped;
      notifyListeners();
    } on CameraException catch (_) {
      // Ignore rapid slider movement errors
    }
  }

  Future<void> setExposureOffset(double value) async {
    final clamped = value.clamp(_minExposure, _maxExposure);
    try {
      await _controller?.setExposureOffset(clamped);
      _exposureOffset = clamped;
      notifyListeners();
    } on CameraException catch (_) {
      // Ignore rapid slider movement errors
    }
  }

  /// Tap-to-focus/expose at a normalized point (0..1, 0..1) within the preview.
  Future<void> setFocusAndExposurePoint(Offset point) async {
    if (_controller == null) return;
    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
    } on CameraException catch (_) {
      // Ignore tap-to-focus errors if camera is busy or closing
    }
  }

  Future<XFile> takePicture() => _controller!.takePicture();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
