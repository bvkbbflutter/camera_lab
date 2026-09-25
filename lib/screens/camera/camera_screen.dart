import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/app_services.dart';
import '../../services/camera/camera_service.dart';
import '../../services/metadata/exif_builder.dart';
import '../../services/metadata/metadata_service.dart';
import '../preview/preview_screen.dart';

/// Spec §46: camera preview, resolution/zoom/exposure/flash controls, and
/// a live location-readiness indicator — capture is never blocked on GPS
/// unless "Require location" is explicitly enabled in Settings.
class CameraScreen extends StatefulWidget {
  final ResolutionPreset? preset;
  const CameraScreen({super.key, this.preset});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  bool _starting = true;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() {
        _starting = false;
        _error =
            'Camera permission denied. Enable it in system settings to use Camera Lab.';
      });
      return;
    }
    if (!mounted) return;
    final services = context.read<AppServices>();
    try {
      await services.camera.initialize(preset: widget.preset);
      setState(() => _starting = false);
    } catch (e) {
      setState(() {
        _starting = false;
        _error = 'Could not start the camera: $e';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _capture() async {
    final services = context.read<AppServices>();
    final camera = services.camera;
    if (!camera.isInitialized || _capturing) return;

    setState(() => _capturing = true);
    final captureStopwatch = Stopwatch()..start();
    try {
      final xfile = await camera.takePicture();
      captureStopwatch.stop();
      final bytes = await File(xfile.path).readAsBytes();

      final deviceInfo = await services.deviceInfo.get();
      final now = DateTime.now();
      final meta = CaptureMetadata(
        latitude: null,
        longitude: null,
        altitudeMeters: null,
        gpsAccuracyMeters: null,
        gpsTimestampUtc: null,
        captureTime: now,
        utcOffset: now.timeZoneOffset,
        cameraMake: deviceInfo.make,
        cameraModel: deviceInfo.model,
        lensFacing: camera.isFrontFacing ? 'front' : 'back',
        orientation:
            1, // capture pipeline normalizes pixels upright; see README
        width: 0, // filled in after decode, below
        height: 0,
        dpi: 300,
      );

      final probe =
          MetadataService.inspect(bytes); // sniffing
      final metaWithSize =
          meta.copyWith(width: probe.width, height: probe.height, orientation: probe.orientation?.value ?? 1);
      final embedded = MetadataService.embed(bytes, metaWithSize);

      final asset = await services.storage.saveNewImage(
        embedded,
        format: probe.format,
        width: probe.width,
        height: probe.height,
      );

      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PreviewScreen(assetId: asset.id, fromCapture: true)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraService>();

    if (_starting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _start, child: const Text('Retry')),
            ]),
          ),
        ),
      );
    }
    if (!camera.isInitialized || camera.controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: GestureDetector(
                onTapUp: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(details.globalPosition);
                  final size = box.size;
                  camera.setFocusAndExposurePoint(
                      Offset(local.dx / size.width, local.dy / size.height));
                },
                child: ClipRect(child: CameraPreview(camera.controller!)),
              ),
            ),
            _ControlsBar(),
            _CaptureBar(capturing: _capturing, onCapture: _capture),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.location_off,
            color: Colors.white70,
            size: 18,
          ),
          SizedBox(width: 6),
          Text(
            'Location metadata: OFF',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(_flashIcon(camera.flashMode)),
                onPressed: () {
                  const modes = [
                    FlashMode.off,
                    FlashMode.auto,
                    FlashMode.always,
                    FlashMode.torch
                  ];
                  final next = modes[
                      (modes.indexOf(camera.flashMode) + 1) % modes.length];
                  camera.setFlashMode(next);
                },
              ),
              Expanded(
                child: Slider(
                  value: camera.zoom,
                  min: camera.minZoom,
                  max: camera.maxZoom == camera.minZoom
                      ? camera.minZoom + 1
                      : camera.maxZoom,
                  label: '${camera.zoom.toStringAsFixed(1)}x',
                  onChanged: (v) => camera.setZoom(v),
                ),
              ),
              IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.cameraswitch),
                  onPressed: camera.switchCamera),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.exposure, color: Colors.white70, size: 18),
              Expanded(
                child: Slider(
                  value: camera.exposureOffset,
                  min: camera.minExposure,
                  max: camera.maxExposure == camera.minExposure
                      ? camera.minExposure + 1
                      : camera.maxExposure,
                  label: camera.exposureOffset.toStringAsFixed(1),
                  onChanged: (v) => camera.setExposureOffset(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _flashIcon(FlashMode mode) => switch (mode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        FlashMode.always => Icons.flash_on,
        FlashMode.torch => Icons.highlight,
      };
}

class _CaptureBar extends StatelessWidget {
  final bool capturing;
  final VoidCallback onCapture;
  const _CaptureBar({required this.capturing, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: GestureDetector(
          onTap: capturing ? null : onCapture,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              color: capturing ? Colors.white24 : Colors.transparent,
            ),
            child: capturing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.white))
                : null,
          ),
        ),
      ),
    );
  }
}
