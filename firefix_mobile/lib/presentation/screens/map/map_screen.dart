import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/emergency_facility.dart';
import '../../../data/services/emergency_map_service.dart';

enum _FacilityFilter { all, fire, medical }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  static const _nairobiCenter = LatLng(-1.2921, 36.8219);

  final MapController _mapController = MapController();
  final EmergencyMapService _mapService = EmergencyMapService();

  StreamSubscription<Position>? _locationSub;
  Position? _userPosition;
  LatLng _searchCenter = _nairobiCenter;
  _FacilityFilter _filter = _FacilityFilter.all;

  List<EmergencyFacility> _facilities = [];
  EmergencyFacility? _selectedFacility;
  EmergencyRoute? _route;
  bool _loadingLocation = true;
  bool _loadingFacilities = true;
  bool _loadingRoute = false;
  bool _liveFacilitiesLoaded = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    _bootstrapMap();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  LatLng get _userLatLng => _userPosition == null
      ? _searchCenter
      : LatLng(_userPosition!.latitude, _userPosition!.longitude);

  List<EmergencyFacility> get _filteredFacilities {
    return switch (_filter) {
      _FacilityFilter.fire =>
        _facilities.where((facility) => facility.isFireStation).toList(),
      _FacilityFilter.medical =>
        _facilities.where((facility) => !facility.isFireStation).toList(),
      _FacilityFilter.all => _facilities,
    };
  }

  Future<void> _bootstrapMap() async {
    await _startLocationTracking();
    await _loadFacilities();
  }

  Future<void> _startLocationTracking() async {
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;

      _searchCenter = LatLng(position.latitude, position.longitude);
      setState(() => _userPosition = position);
      _mapController.move(_searchCenter, 14);

      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() => _userPosition = position);
      });
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _loadFacilities() async {
    setState(() {
      _loadingFacilities = true;
      _selectedFacility = null;
      _route = null;
      _liveFacilitiesLoaded = false;
      _facilities = _mapService.seedNearbyFacilities(center: _searchCenter);
    });

    if (mounted) {
      setState(() => _loadingFacilities = false);
    }

    if (_facilities.isNotEmpty) {
      await _selectFacility(_facilities.first, fitMap: true);
    }

    unawaited(_refreshLiveFacilities());
  }

  Future<void> _refreshLiveFacilities() async {
    try {
      final facilities = await _mapService.fetchNearbyFacilities(
        center: _searchCenter,
      );
      if (!mounted || facilities.isEmpty) return;

      final selectedId = _selectedFacility?.id;
      setState(() {
        _facilities = facilities;
        _liveFacilitiesLoaded = true;
      });

      final selectedExists =
          selectedId != null && facilities.any((item) => item.id == selectedId);
      if (!selectedExists) {
        await _selectFacility(facilities.first, fitMap: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _liveFacilitiesLoaded = false);
      }
    }
  }

  Future<void> _selectFacility(
    EmergencyFacility facility, {
    bool fitMap = false,
  }) async {
    final estimatedRoute = _mapService.estimateRoute(
      from: _userLatLng,
      to: facility.location,
    );
    setState(() {
      _selectedFacility = facility;
      _loadingRoute = false;
      _route = estimatedRoute;
    });

    if (fitMap) _fitRoute(estimatedRoute.points);

    unawaited(_refreshLiveRoute(facility));
  }

  Future<void> _refreshLiveRoute(EmergencyFacility facility) async {
    try {
      final route = await _mapService.fetchDrivingRoute(
        from: _userLatLng,
        to: facility.location,
      );
      if (!mounted || _selectedFacility?.id != facility.id) return;

      setState(() => _route = route);
      if (route.points.length > 1) _fitRoute(route.points);
    } catch (_) {
      // Keep the estimated route already on screen.
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 260),
      ),
    );
  }

  void _recenter() {
    _mapController.move(_userLatLng, 14);
  }

  Future<void> _openDirections(EmergencyFacility facility) async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car'
      '&route=${_userLatLng.latitude}%2C${_userLatLng.longitude}%3B'
      '${facility.location.latitude}%2C${facility.location.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callFacility(EmergencyFacility facility) async {
    final phone = facility.phone;
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final facilities = _filteredFacilities;

    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _searchCenter,
                      initialZoom: 13,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.bouric.karada',
                      ),
                      if (_route != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _route!.points,
                              color: _route!.isEstimated
                                  ? AppColors.tertiaryDark
                                  : AppColors.secondary,
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          ...facilities.map(_facilityMarker),
                          _userMarker(),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _buildFilterBar(),
                        const SizedBox(height: 8),
                        _buildStatusBanner(),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: _selectedFacility == null ? 132 : 268,
                    child: _buildMapControls(),
                  ),
                  if (_loadingFacilities)
                    const Positioned.fill(child: _MapLoadingOverlay()),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _selectedFacility == null
                        ? _buildFacilityStrip(facilities)
                        : _buildFacilityCard(_selectedFacility!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _facilityMarker(EmergencyFacility facility) {
    final selected = _selectedFacility?.id == facility.id;
    final color =
        facility.isFireStation ? AppColors.primary : AppColors.success;
    return Marker(
      point: facility.location,
      width: selected ? 58 : 48,
      height: selected ? 58 : 48,
      child: GestureDetector(
        onTap: () => _selectFacility(facility, fitMap: true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: selected ? 3 : 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacitySafe(selected ? 0.42 : 0.25),
                blurRadius: selected ? 18 : 10,
                spreadRadius: selected ? 2 : 0,
              ),
            ],
          ),
          child: Icon(
            facility.isFireStation
                ? Icons.fire_truck_rounded
                : Icons.local_hospital_rounded,
            color: Colors.white,
            size: selected ? 26 : 21,
          ),
        ),
      ),
    );
  }

  Marker _userMarker() {
    return Marker(
      point: _userLatLng,
      width: 58,
      height: 58,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1.2 + (_pulseAnimation.value * 0.45),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withOpacitySafe(0.16),
                    border: Border.all(
                      color: Colors.blue.withOpacitySafe(0.28),
                    ),
                  ),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final fireCount = _facilities.where((item) => item.isFireStation).length;
    final medicalCount = _facilities.length - fireCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: const BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacitySafe(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emergency_share_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Response Map',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'OpenStreetMap responders near you',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          _HeaderStat(icon: Icons.fire_truck_rounded, value: '$fireCount'),
          const SizedBox(width: 8),
          _HeaderStat(
              icon: Icons.local_hospital_rounded, value: '$medicalCount'),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacitySafe(0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _filterChip('All', Icons.public_rounded, _FacilityFilter.all),
          _filterChip('Fire', Icons.fire_truck_rounded, _FacilityFilter.fire),
          _filterChip(
            'Medical',
            Icons.local_hospital_rounded,
            _FacilityFilter.medical,
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, _FacilityFilter value) {
    final selected = _filter == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _filter = value;
          _selectedFacility = null;
          _route = null;
        }),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          decoration: BoxDecoration(
            color: selected ? AppColors.dark : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : AppColors.muted,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.dark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      children: [
        _MapButton(
          icon: Icons.my_location_rounded,
          tooltip: 'Center on my location',
          onTap: _recenter,
        ),
        const SizedBox(height: 10),
        _MapButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh responders',
          onTap: _loadFacilities,
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.tips_and_updates_rounded,
              color: AppColors.dark, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadingFacilities
                  ? 'Finding nearby responders...'
                  : !_liveFacilitiesLoaded
                      ? 'Using local responder coverage until live data is available.'
                      : 'Nearby responders are ready.',
              style: const TextStyle(
                color: AppColors.dark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityStrip(List<EmergencyFacility> facilities) {
    if (facilities.isEmpty) {
      return _BottomPanel(
        child: Row(
          children: [
            const Icon(Icons.search_off_rounded, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _loadingLocation
                    ? 'Finding your location...'
                    : 'No emergency responders found nearby.',
                style: const TextStyle(
                  color: AppColors.dark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final nearest = facilities.take(3).toList();
    return _BottomPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Nearest responders',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 10),
          ...nearest.map(
            (facility) => _FacilityListTile(
              facility: facility,
              onTap: () => _selectFacility(facility, fitMap: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityCard(EmergencyFacility facility) {
    final color =
        facility.isFireStation ? AppColors.primary : AppColors.success;
    return _BottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacitySafe(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  facility.isFireStation
                      ? Icons.fire_truck_rounded
                      : Icons.local_hospital_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      facility.address ?? facility.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _selectedFacility = null;
                  _route = null;
                }),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(
                icon: Icons.near_me_rounded,
                label: 'Distance',
                value: _distanceLabel(facility.distanceMeters),
              ),
              const SizedBox(width: 10),
              _Metric(
                icon: Icons.timer_rounded,
                label: _route?.isEstimated == true ? 'ETA est.' : 'ETA',
                value: _loadingRoute
                    ? '...'
                    : '${_route?.durationMinutes ?? 0} min',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openDirections(facility),
                  icon: const Icon(Icons.route_rounded, size: 18),
                  label: const Text('Open route'),
                ),
              ),
              const SizedBox(width: 10),
              if (facility.phone != null && facility.phone!.trim().isNotEmpty)
                SizedBox(
                  width: 52,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => _callFacility(facility),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.call_rounded),
                  ),
                ),
            ],
          ),
          if (AppConstants.openRouteApiKey.isEmpty ||
              _route?.isEstimated == true)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Route is estimated until OpenRouteService returns a route.',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacitySafe(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: AppColors.dark),
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacitySafe(0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FacilityListTile extends StatelessWidget {
  const _FacilityListTile({required this.facility, required this.onTap});

  final EmergencyFacility facility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        facility.isFireStation ? AppColors.primary : AppColors.success;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacitySafe(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                facility.isFireStation
                    ? Icons.fire_truck_rounded
                    : Icons.local_hospital_rounded,
                color: color,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    facility.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  Text(
                    facility.typeLabel,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              facility.distanceMeters >= 1000
                  ? '${(facility.distanceMeters / 1000).toStringAsFixed(1)} km'
                  : '${facility.distanceMeters.round()} m',
              style: const TextStyle(
                color: AppColors.dark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.neutral,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.secondary, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.dark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLoadingOverlay extends StatelessWidget {
  const _MapLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 10),
              Text(
                'Loading nearby responders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
