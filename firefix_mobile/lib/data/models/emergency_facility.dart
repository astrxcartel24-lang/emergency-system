import 'package:latlong2/latlong.dart';

enum EmergencyFacilityType { fireStation, medical }

class EmergencyFacility {
  final String id;
  final String name;
  final EmergencyFacilityType type;
  final LatLng location;
  final String? phone;
  final String? address;
  final double distanceMeters;

  const EmergencyFacility({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    this.phone,
    this.address,
    required this.distanceMeters,
  });

  bool get isFireStation => type == EmergencyFacilityType.fireStation;

  String get typeLabel => isFireStation ? 'Fire station' : 'Medical facility';
}

class EmergencyRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isEstimated;

  const EmergencyRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isEstimated,
  });

  int get durationMinutes => (durationSeconds / 60).ceil().clamp(1, 999);

  double get distanceKilometers => distanceMeters / 1000;
}
