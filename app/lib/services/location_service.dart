import 'dart:async';

import 'package:geocoding/geocoding.dart';
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

/// Address suggested from GPS (Android's free on-device geocoder).
class GpsAddress {
  GpsAddress({
    this.street = '',
    this.street2 = '',
    this.city = '',
    this.zip = '',
    this.state = '',
    this.countryCode = '',
  });

  final String street;
  final String street2;
  final String city;
  final String zip;
  final String state;
  final String countryCode;

  bool get isEmpty => street.isEmpty && city.isEmpty && zip.isEmpty;
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

  static Future<GpsAddress?> addressFor(double lat, double lng) async {
    try {
      final places = await Geocoding()
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 12));
      if (places.isEmpty) return null;
      final p = places.first;
      String s(String? v) => (v ?? '').trim();

      final number = s(p.subThoroughfare);
      final road = s(p.thoroughfare);
      var street = [number, road].where((e) => e.isNotEmpty).join(', ');
      if (street.isEmpty) street = s(p.street);
      // Android often returns a Plus Code (e.g. "X7QF+2M") as street; skip it.
      if (RegExp(r'^[23456789CFGHJMPQRVWX]{4,}\+').hasMatch(street)) street = '';

      final area = s(p.subLocality);
      final city = s(p.locality).isNotEmpty ? s(p.locality) : s(p.subAdministrativeArea);
      return GpsAddress(
        street: street,
        street2: area == city ? '' : area,
        city: city,
        zip: s(p.postalCode),
        state: s(p.administrativeArea),
        countryCode: s(p.isoCountryCode).toUpperCase(),
      );
    } catch (_) {
      return null; // offline or no geocoder on this phone
    }
  }
}
