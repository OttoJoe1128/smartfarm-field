import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../config/api_config.dart';

/// GPS hassasiyet seviyeleri
enum GpsAccuracyLevel {
  excellent, // < 2m
  good,      // < 5m
  fair,      // < 10m
  poor,      // > 10m
}

/// GPS konum verisi
class GpsPosition {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double accuracy;
  final GpsAccuracyLevel accuracyLevel;
  final DateTime timestamp;

  const GpsPosition({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.accuracy,
    required this.accuracyLevel,
    required this.timestamp,
  });
}

/// Yuksek hassasiyetli GPS servisi
/// Saha veri toplama icin optimize edilmis konum hizmetleri
class GpsService {
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  final StreamController<GpsPosition> _positionController =
      StreamController<GpsPosition>.broadcast();

  /// Konum akisi - dinleyiciler icin
  Stream<GpsPosition> get positionStream => _positionController.stream;

  /// Son bilinen konum
  GpsPosition? get lastKnownPosition => _lastPosition != null
      ? _convertPosition(_lastPosition!)
      : null;

  /// Konum servislerinin kullanilabilir olup olmadigini kontrol et
  Future<bool> checkLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Konum izni kontrol et ve iste
  Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Izin verilmis mi kontrol et
  Future<bool> hasPermission() async {
    final LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Tek seferlik yuksek hassasiyet konum al
  Future<GpsPosition> getCurrentPosition() async {
    final bool isServiceEnabled = await checkLocationServiceEnabled();
    if (!isServiceEnabled) {
      throw GpsException('Konum servisleri kapali. Lutfen aciniz.');
    }
    final bool isPermitted = await hasPermission();
    if (!isPermitted) {
      final LocationPermission permission = await requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw GpsException('Konum izni reddedildi.');
      }
    }
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    );
    _lastPosition = position;
    final GpsPosition gpsPosition = _convertPosition(position);
    _positionController.add(gpsPosition);
    return gpsPosition;
  }

  /// Yuksek hassasiyet surekli izleme baslat
  Future<void> startHighAccuracyTracking() async {
    final bool isServiceEnabled = await checkLocationServiceEnabled();
    if (!isServiceEnabled) {
      throw GpsException('Konum servisleri kapali. Lutfen aciniz.');
    }
    final bool isPermitted = await hasPermission();
    if (!isPermitted) {
      throw GpsException('Konum izni verilmedi.');
    }
    await stopTracking();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(
      (Position position) {
        _lastPosition = position;
        final GpsPosition gpsPosition = _convertPosition(position);
        _positionController.add(gpsPosition);
      },
      onError: (dynamic error) {
        debugPrint('GPS izleme hatasi: $error');
      },
    );
  }

  /// Surekli izlemeyi durdur
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Hassasiyet seviyesini hesapla
  static GpsAccuracyLevel calculateAccuracyLevel(double accuracyMeters) {
    if (accuracyMeters < ApiConfig.excellentAccuracyMeters) {
      return GpsAccuracyLevel.excellent;
    } else if (accuracyMeters < ApiConfig.goodAccuracyMeters) {
      return GpsAccuracyLevel.good;
    } else if (accuracyMeters < ApiConfig.fairAccuracyMeters) {
      return GpsAccuracyLevel.fair;
    } else {
      return GpsAccuracyLevel.poor;
    }
  }

  /// Hassasiyet yeterli mi kontrol et
  static bool isAccuracySufficient(double accuracyMeters) {
    return accuracyMeters <= ApiConfig.minimumAccuracyMeters;
  }

  /// GPS atlama tespiti - onceki noktadan cok uzak mi
  bool hasJumpedFromLastPosition(double latitude, double longitude) {
    if (_lastPosition == null) return false;
    final double distance = _calculateDistance(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      latitude,
      longitude,
    );
    return distance > ApiConfig.jumpDistanceWarningMeters;
  }

  /// Hassasiyet seviyesi icin goruntuleme metni
  static String accuracyLevelDisplayName(GpsAccuracyLevel level) {
    switch (level) {
      case GpsAccuracyLevel.excellent:
        return 'Mukemmel';
      case GpsAccuracyLevel.good:
        return 'Iyi';
      case GpsAccuracyLevel.fair:
        return 'Orta';
      case GpsAccuracyLevel.poor:
        return 'Zayif';
    }
  }

  /// Position'i GpsPosition'a donustur
  GpsPosition _convertPosition(Position position) {
    return GpsPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude != 0.0 ? position.altitude : null,
      accuracy: position.accuracy,
      accuracyLevel: calculateAccuracyLevel(position.accuracy),
      timestamp: position.timestamp,
    );
  }

  /// Iki nokta arasi mesafe hesapla (Haversine formulu, metre)
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // metre
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  /// Servisi temizle
  void dispose() {
    stopTracking();
    _positionController.close();
  }
}

/// GPS ozel hata sinifi
class GpsException implements Exception {
  final String message;
  const GpsException(this.message);

  @override
  String toString() => 'GpsException: $message';
}
