class IncidentModel {
  final String type; // fire, medical, accident, crime, protest
  final String description;
  final double latitude;
  final double longitude;
  final String severity; // low, medium, high, critical
  final String reportedBy;

  IncidentModel({
    required this.type,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.severity,
    this.reportedBy = 'app',
  });

  /// Maps Flutter model → Go backend's CreateIncidentRequest JSON shape
  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'severity': severity,
        'reported_by': reportedBy,
      };

  /// Maps Go backend's Incident JSON → Flutter model
  factory IncidentModel.fromJson(Map<String, dynamic> json) => IncidentModel(
        type: json['type'] as String? ?? 'other',
        description: json['description'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        severity: json['severity'] as String? ?? 'medium',
        reportedBy: json['reported_by'] as String? ?? 'app',
      );
}