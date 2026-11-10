import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationProblem { serviceOff, denied, deniedForever, approximate }

class LocationProblemException implements Exception {
  LocationProblemException(this.problem);
  final LocationProblem problem;

  String get message => switch (problem) {
    LocationProblem.serviceOff => 'Location (GPS) is turned off on this phone.',
    LocationProblem.denied => 'Location permission is needed to set the customer location.',
    LocationProblem.deniedForever =>
      'Location permission is blocked. Allow it in Settings › Apps › VeeVee Field Locator › Permissions.',
    LocationProblem.approximate =>
      'The app has only approximate location, which can be off by a kilometre. '
          'In Settings › Apps › VeeVee Field Locator › Permissions › Location, turn on "Use precise location".',
  };
}

class LocationService {
  /// Checks GPS is on and permission is granted (asks if needed).
  static Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationProblemException(LocationProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationProblemException(LocationProblem.deniedForever);
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
      throw LocationProblemException(LocationProblem.denied);
    }
    // Android 12+: the person may have chosen "Approximate" in the dialog.
    try {
      if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
        throw LocationProblemException(LocationProblem.approximate);
      }
    } on LocationProblemException {
      rethrow;
    } catch (_) {
      // Older Android: always precise.
    }
  }

  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Live positions, about one per second, best accuracy.
  static Stream<Position> positions() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      ),
    );
  }
}
