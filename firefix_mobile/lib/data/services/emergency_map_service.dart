import 'dart:developer' as developer;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_constants.dart';
import '../models/emergency_facility.dart';

class EmergencyMapService {
  EmergencyMapService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      responseType: ResponseType.json,
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            developer.log(
              '→ ${options.method} ${options.uri}',
              name: 'KaradaMap',
            );
            handler.next(options);
          },
          onResponse: (response, handler) {
            developer.log(
              '← ${response.statusCode} ${response.requestOptions.uri}',
              name: 'KaradaMap',
            );
            handler.next(response);
          },
          onError: (error, handler) {
            developer.log(
              '× ${error.requestOptions.method} ${error.requestOptions.uri} '
              '${error.response?.statusCode ?? ''} ${error.message}',
              name: 'KaradaMap',
            );
            handler.next(error);
          },
        ),
      );
    }
  }

  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const _openRouteBaseUrl = 'https://api.openrouteservice.org';

  final Dio _dio;
  final Distance _distance = const Distance();

  bool get _hasBackend => AppConstants.mapBackendBaseUrl.isNotEmpty;

  Future<List<EmergencyFacility>> fetchNearbyFacilities({
    required LatLng center,
    int radiusMeters = 10000,
  }) async {
    if (_hasBackend) {
      try {
        final response = await _dio.get(
          '${AppConstants.mapBackendBaseUrl}/facilities',
          queryParameters: {
            'lat': center.latitude,
            'lng': center.longitude,
            'radius': radiusMeters,
          },
        );

        final facilities = (response.data['facilities'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => EmergencyFacility(
                id: item['id'] as String? ?? '',
                name: item['name'] as String? ?? 'Unknown responder',
                type: (item['type'] as String? ?? 'medical') == 'fire'
                    ? EmergencyFacilityType.fireStation
                    : EmergencyFacilityType.medical,
                location: LatLng(
                  (item['lat'] as num).toDouble(),
                  (item['lng'] as num).toDouble(),
                ),
                phone: item['phone'] as String?,
                address: item['address'] as String?,
                distanceMeters: (item['distanceMeters'] as num).toDouble(),
              ),
            )
            .toList()
          ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

        if (facilities.isNotEmpty) {
          return _dedupeFacilities(facilities);
        }
      } catch (error) {
        developer.log(
          'backend facilities fallback: $error',
          name: 'KaradaMap',
        );
        return _seedFacilities(center);
      }
    }

    try {
      final query = '''
[out:json][timeout:25];
(
  node["amenity"="fire_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  way["amenity"="fire_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  relation["amenity"="fire_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  node["amenity"~"hospital|clinic|doctors"](around:$radiusMeters,${center.latitude},${center.longitude});
  way["amenity"~"hospital|clinic|doctors"](around:$radiusMeters,${center.latitude},${center.longitude});
  relation["amenity"~"hospital|clinic|doctors"](around:$radiusMeters,${center.latitude},${center.longitude});
  node["healthcare"~"hospital|clinic|doctor"](around:$radiusMeters,${center.latitude},${center.longitude});
  way["healthcare"~"hospital|clinic|doctor"](around:$radiusMeters,${center.latitude},${center.longitude});
  relation["healthcare"~"hospital|clinic|doctor"](around:$radiusMeters,${center.latitude},${center.longitude});
  node["emergency"="ambulance_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  way["emergency"="ambulance_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  relation["emergency"="ambulance_station"](around:$radiusMeters,${center.latitude},${center.longitude});
);
out center tags;
''';

      final response = await _dio.post(
        _overpassUrl,
        data: query,
        options: Options(contentType: Headers.textPlainContentType),
      );

      final elements = (response.data['elements'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();

      final facilities = elements
          .map((element) => _facilityFromOverpass(element, center))
          .whereType<EmergencyFacility>()
          .toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      final deduped = _dedupeFacilities(facilities);
      if (deduped.isNotEmpty) {
        return deduped;
      }
    } catch (error) {
      developer.log(
        'overpass facilities fallback: $error',
        name: 'KaradaMap',
      );
    }

    return _seedFacilities(center);
  }

  List<EmergencyFacility> seedNearbyFacilities({
    required LatLng center,
  }) {
    return _seedFacilities(center);
  }

  EmergencyRoute estimateRoute({
    required LatLng from,
    required LatLng to,
  }) {
    return _estimatedRoute(from, to);
  }

  Future<EmergencyRoute> fetchDrivingRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    if (_hasBackend) {
      try {
        final response = await _dio.post(
          '${AppConstants.mapBackendBaseUrl}/route',
          data: {
            'from': {'lat': from.latitude, 'lng': from.longitude},
            'to': {'lat': to.latitude, 'lng': to.longitude},
          },
        );

        final route = response.data['route'] as Map<String, dynamic>;
        final points = (route['points'] as List)
            .whereType<Map<String, dynamic>>()
            .map(
              (point) => LatLng(
                (point['lat'] as num).toDouble(),
                (point['lng'] as num).toDouble(),
              ),
            )
            .toList();

        if (points.isNotEmpty) {
          return EmergencyRoute(
            points: points,
            distanceMeters: (route['distanceMeters'] as num).toDouble(),
            durationSeconds: (route['durationSeconds'] as num).toDouble(),
            isEstimated: route['isEstimated'] as bool? ?? false,
          );
        }
      } catch (error) {
        developer.log(
          'backend route fallback: $error',
          name: 'KaradaMap',
        );
      }
    }

    if (AppConstants.openRouteApiKey.isEmpty) {
      return _estimatedRoute(from, to);
    }

    try {
      final response = await _dio.post(
        '$_openRouteBaseUrl/v2/directions/driving-car/geojson',
        data: {
          'coordinates': [
            [from.longitude, from.latitude],
            [to.longitude, to.latitude],
          ],
        },
        options: Options(
          headers: {'Authorization': AppConstants.openRouteApiKey},
        ),
      );

      final feature = (response.data['features'] as List).first;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>;
      final summary = properties['summary'] as Map<String, dynamic>;
      final coordinates = (geometry['coordinates'] as List)
          .whereType<List>()
          .map(
            (point) => LatLng(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
            ),
          )
          .toList();

      return EmergencyRoute(
        points: coordinates,
        distanceMeters: (summary['distance'] as num).toDouble(),
        durationSeconds: (summary['duration'] as num).toDouble(),
        isEstimated: false,
      );
    } catch (_) {
      return _estimatedRoute(from, to);
    }
  }

  List<EmergencyFacility> _dedupeFacilities(List<EmergencyFacility> items) {
    final seen = <String>{};
    return items
        .where((facility) {
          final key = facility.name.toLowerCase().trim();
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        })
        .take(30)
        .toList();
  }

  EmergencyFacility? _facilityFromOverpass(
    Map<String, dynamic> element,
    LatLng center,
  ) {
    final lat = (element['lat'] ?? element['center']?['lat']) as num?;
    final lon = (element['lon'] ?? element['center']?['lon']) as num?;
    if (lat == null || lon == null) return null;

    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    final location = LatLng(lat.toDouble(), lon.toDouble());
    final type = _typeFromTags(tags);
    final name = (tags['name'] as String?)?.trim();

    return EmergencyFacility(
      id: '${element['type']}-${element['id']}',
      name: name == null || name.isEmpty ? _fallbackName(type) : name,
      type: type,
      location: location,
      phone: tags['phone'] as String?,
      address: _addressFromTags(tags),
      distanceMeters: _distance.as(LengthUnit.Meter, center, location),
    );
  }

  EmergencyFacilityType _typeFromTags(Map<String, dynamic> tags) {
    if (tags['amenity'] == 'fire_station') {
      return EmergencyFacilityType.fireStation;
    }
    return EmergencyFacilityType.medical;
  }

  String _fallbackName(EmergencyFacilityType type) {
    return type == EmergencyFacilityType.fireStation
        ? 'Unnamed fire station'
        : 'Unnamed medical facility';
  }

  String? _addressFromTags(Map<String, dynamic> tags) {
    final parts = [
      tags['addr:street'],
      tags['addr:suburb'],
      tags['addr:city'],
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  EmergencyRoute _estimatedRoute(LatLng from, LatLng to) {
    final distanceMeters = _distance.as(LengthUnit.Meter, from, to);
    final durationSeconds = max(90, distanceMeters / 7.5);
    return EmergencyRoute(
      points: [from, to],
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds.toDouble(),
      isEstimated: true,
    );
  }

  List<EmergencyFacility> _seedFacilities(LatLng center) {
    const seeds = <Map<String, Object?>>[
      {
        'id': 'seed-fire-1',
        'name': 'Nairobi Central Fire Station',
        'type': 'fire',
        'lat': -1.2833,
        'lng': 36.8167,
        'address': 'Central Business District, Nairobi',
        'phone': '0800723999',
      },
      {
        'id': 'seed-fire-2',
        'name': 'Eastlands Fire Station',
        'type': 'fire',
        'lat': -1.3102,
        'lng': 36.8303,
        'address': 'Eastlands, Nairobi',
        'phone': '0800723999',
      },
      {
        'id': 'seed-med-1',
        'name': 'Kenyatta National Hospital',
        'type': 'medical',
        'lat': -1.3032,
        'lng': 36.8078,
        'address': 'Hospital Road, Nairobi',
        'phone': '+254202720630',
      },
      {
        'id': 'seed-med-2',
        'name': 'Mbagathi Hospital',
        'type': 'medical',
        'lat': -1.3184,
        'lng': 36.7897,
        'address': 'Mbagathi Way, Nairobi',
        'phone': '+254202755453',
      },
    ];

    return seeds
        .map(
          (item) => EmergencyFacility(
            id: item['id']! as String,
            name: item['name']! as String,
            type: item['type'] == 'fire'
                ? EmergencyFacilityType.fireStation
                : EmergencyFacilityType.medical,
            location: LatLng(
              item['lat']! as double,
              item['lng']! as double,
            ),
            phone: item['phone'] as String?,
            address: item['address'] as String?,
            distanceMeters: _distance.as(
              LengthUnit.Meter,
              center,
              LatLng(item['lat']! as double, item['lng']! as double),
            ),
          ),
        )
        .toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  }
}
