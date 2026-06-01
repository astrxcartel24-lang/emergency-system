import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/incident_model.dart';
import '../../core/constants/app_constants.dart';

class IncidentService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // ── Report a new incident ──────────────────────────────────────────────────

  /// Returns the created incident ID on success, throws on failure.
  Future<String> reportIncident(IncidentModel incident) async {
    final response = await _dio.post(
      AppConstants.incidentEndpoint,
      data: incident.toJson(),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data as Map<String, dynamic>;
      return data['id'] as String? ?? '';
    }
    throw Exception('Server returned ${response.statusCode}');
  }

  // ── Fetch all incidents ────────────────────────────────────────────────────

  Future<List<IncidentModel>> fetchIncidents() async {
    final response = await _dio.get(AppConstants.incidentEndpoint);
    if (response.statusCode == 200) {
      final List<dynamic> list = response.data as List<dynamic>;
      return list
          .map((e) => IncidentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load incidents: ${response.statusCode}');
  }

  // ── Fetch nearby incidents ─────────────────────────────────────────────────

  Future<List<IncidentModel>> fetchNearby({
    required double lat,
    required double lng,
    double radiusKm = 5,
  }) async {
    final response = await _dio.get(
      AppConstants.nearbyEndpoint,
      queryParameters: {'lat': lat, 'lng': lng, 'radius': radiusKm},
    );
    if (response.statusCode == 200) {
      final List<dynamic> list = response.data as List<dynamic>;
      return list
          .map((e) => IncidentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load nearby incidents');
  }

  // ── Health check ───────────────────────────────────────────────────────────

  Future<bool> isBackendReachable() async {
    try {
      final response = await _dio.get(
        AppConstants.healthEndpoint,
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}