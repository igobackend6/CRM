import 'package:geolocator/geolocator.dart' as geo;

/// A resolved GPS fix — just the two columns `leads` already has
/// (`latitude`/`longitude`, 000008_leads.sql), nothing plugin-specific
/// left in it.
class LocationResult {
  const LocationResult({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Thin abstraction over `geolocator` — same "swap out a real plugin
/// for a fake in tests" seam as ExternalUrlLauncher/DocumentFilePicker,
/// since `flutter test` has no platform channel to actually check
/// permissions or read a GPS fix.
abstract class LocationService {
  /// True once the device reports permission already granted (does not
  /// prompt) — used to show "Location enabled" instead of "Grant" on
  /// screens that were already granted in an earlier session.
  Future<bool> hasPermission();

  /// Prompts for permission/location-services if needed, then returns
  /// the current fix. Null covers every way this can fail to produce a
  /// position (services off, permission denied or permanently denied,
  /// a read timeout) — the UI treats all of them the same way ("Grant"
  /// stays, with a explanatory message), it doesn't need to distinguish
  /// which.
  Future<LocationResult?> requestAndGetLocation();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<bool> hasPermission() async {
    final permission = await geo.Geolocator.checkPermission();
    return permission == geo.LocationPermission.always || permission == geo.LocationPermission.whileInUse;
  }

  @override
  Future<LocationResult?> requestAndGetLocation() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) return null;

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.medium),
      );
      return LocationResult(latitude: position.latitude, longitude: position.longitude);
    } on Exception {
      return null;
    }
  }
}
