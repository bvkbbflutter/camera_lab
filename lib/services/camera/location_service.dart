// import 'package:geolocator/geolocator.dart';

// /// Result of a location attempt: either a fresh fix, or a clear reason it
// /// wasn't available. The UI must never fabricate coordinates (spec §5:
// /// "Location: Not available" when unavailable).
// class LocationResult {
//   final Position? position;
//   final String? unavailableReason;
//   const LocationResult.ok(this.position) : unavailableReason = null;
//   const LocationResult.unavailable(this.unavailableReason) : position = null;

//   bool get isAvailable => position != null;
// }

// enum LocationPermissionState { granted, denied, permanentlyDenied, restricted, serviceDisabled }

// /// Spec §5/§41/§42/§43: request permission, fetch the current fix as close
// /// to capture time as practical, honor a configurable freshness threshold,
// /// and never block capture unless the caller explicitly asks it to.
// class LocationService {
//   Position? _lastFix;
//   DateTime? _lastFixAt;

//   Future<LocationPermissionState> checkAndRequestPermission() async {
//     final serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) return LocationPermissionState.serviceDisabled;

//     var permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//     }
//     switch (permission) {
//       case LocationPermission.denied:
//         return LocationPermissionState.denied;
//       case LocationPermission.deniedForever:
//         return LocationPermissionState.permanentlyDenied;
//       case LocationPermission.unableToDetermine:
//         return LocationPermissionState.restricted;
//       case LocationPermission.whileInUse:
//       case LocationPermission.always:
//         return LocationPermissionState.granted;
//     }
//   }

//   /// Starts warming up a location fix (call this while preparing the
//   /// camera, per spec §43, so a fix is ready "as close as reasonably
//   /// practical" to the moment the shutter is pressed).
//   Future<void> prewarm() async {
//     try {
//       final state = await checkAndRequestPermission();
//       if (state != LocationPermissionState.granted) return;
//       _lastFix = await Geolocator.getCurrentPosition(
//         locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
//       );
//       _lastFixAt = DateTime.now();
//     } catch (_) {
//       // Leave _lastFix as-is; getCurrentForCapture() will surface the failure.
//     }
//   }

//   /// Returns the warmed-up fix if it's within [maxAge], otherwise takes a
//   /// fresh one. Never throws — capture must never be blocked by GPS
//   /// trouble unless the caller checks isAvailable and enforces that itself.
//   Future<LocationResult> getCurrentForCapture({required Duration maxAge}) async {
//     final state = await checkAndRequestPermission();
//     if (state != LocationPermissionState.granted) {
//       return LocationResult.unavailable(_permissionMessage(state));
//     }

//     if (_lastFix != null && _lastFixAt != null && DateTime.now().difference(_lastFixAt!) <= maxAge) {
//       return LocationResult.ok(_lastFix);
//     }

//     try {
//       final pos = await Geolocator.getCurrentPosition(
//         locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
//       );
//       _lastFix = pos;
//       _lastFixAt = DateTime.now();
//       return LocationResult.ok(pos);
//     } catch (e) {
//       return LocationResult.unavailable('Location unavailable: $e');
//     }
//   }

//   String _permissionMessage(LocationPermissionState state) {
//     switch (state) {
//       case LocationPermissionState.denied:
//         return 'Location permission denied';
//       case LocationPermissionState.permanentlyDenied:
//         return 'Location permission permanently denied — enable it in system settings';
//       case LocationPermissionState.restricted:
//         return 'Location permission restricted';
//       case LocationPermissionState.serviceDisabled:
//         return 'Location services are turned off on this device';
//       case LocationPermissionState.granted:
//         return 'Location unavailable';
//     }
//   }
// }
