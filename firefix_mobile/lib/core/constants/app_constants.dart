import 'package:flutter/material.dart';

class AppConstants {
  // ---------------------------------------------------------------------------
  // API – set BASE_URL at build time via --dart-define=BASE_URL=https://...
  // Falls back to localhost for local dev.
  // ---------------------------------------------------------------------------
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8090', // Android emulator → host localhost
  );

  static const String incidentEndpoint = '/api/v1/incidents';
  static const String nearbyEndpoint = '/api/v1/incidents/nearby';
  static const String healthEndpoint = '/health';

  /// WebSocket endpoint for real-time incident updates
  static String get wsUrl {
    final http = baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    return '$http/api/ws';
  }

  // Map backend (existing)
  static const String mapBackendBaseUrl = String.fromEnvironment(
    'MAP_BACKEND_BASE_URL',
    defaultValue: 'https://karada-map-backend.onrender.com',
  );
  static const String openRouteApiKey = String.fromEnvironment(
    'OPENROUTE_API_KEY',
  );

  // App
  static const String appName = 'Karada';
  static const String emergencyNumber = '0800 723 999';

  // Severity levels — labels in Swahili, values match Go backend
  static const List<Map<String, dynamic>> severityLevels = [
    {
      'label': 'Ndogo',
      'sublabel': 'Small fire, contained',
      'icon': Icons.local_fire_department_rounded,
      'value': 'low'
    },
    {
      'label': 'Wastani',
      'sublabel': 'Spreading, needs response',
      'icon': Icons.local_fire_department_rounded,
      'value': 'medium'
    },
    {
      'label': 'Kubwa',
      'sublabel': 'Large fire, critical',
      'icon': Icons.fire_truck_rounded,
      'value': 'high'
    },
    {
      'label': 'Dharura',
      'sublabel': 'Casualties involved',
      'icon': Icons.emergency_share_rounded,
      'value': 'critical'
    },
  ];
}