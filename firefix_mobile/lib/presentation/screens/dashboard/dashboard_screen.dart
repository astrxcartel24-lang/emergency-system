import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/emergency_facility.dart';
import '../../../data/services/emergency_map_service.dart';
import '../../../data/services/location_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _locationService = LocationService();
  final _mapService = EmergencyMapService();

  Position? _position;
  String _address = '';
  bool _loadingLocation = true;
  bool _loadingFacilities = true;
  List<EmergencyFacility> _facilities = [];

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    await _loadLocation();
    await _loadNearbyFacilities();
  }

  Future<void> _loadLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoords(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _address = address;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _address = 'Location unavailable');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _loadNearbyFacilities() async {
    setState(() => _loadingFacilities = true);
    try {
      final center = _position != null
          ? LatLng(_position!.latitude, _position!.longitude)
          : const LatLng(-1.2921, 36.8219);
      final facilities = await _mapService.fetchNearbyFacilities(
        center: center,
      );
      if (!mounted) return;
      setState(() => _facilities = facilities);
    } catch (_) {
      if (!mounted) return;
      setState(() => _facilities = []);
    } finally {
      if (mounted) setState(() => _loadingFacilities = false);
    }
  }

  Future<void> _callEmergency() async {
    final uri = Uri(scheme: 'tel', path: AppConstants.emergencyNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nearest = _facilities.take(3).toList();

    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildHero(context)),
              SliverToBoxAdapter(child: _buildStats()),
              SliverToBoxAdapter(child: _buildQuickActions(context)),
              SliverToBoxAdapter(
                child: _buildNearbyFacilities(nearest),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Karada Dashboard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Operations overview for emergency response',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          _LiveChip(
            loading: _loadingLocation,
            label: _position == null ? 'GPS' : 'LIVE',
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.dark.withOpacitySafe(0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacitySafe(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sos_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Emergency control center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _address.isEmpty
                  ? 'Your current location will anchor nearby responders and routing.'
                  : _address,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/report'),
                    icon: const Icon(Icons.crisis_alert_rounded, size: 18),
                    label: const Text('Report emergency'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/map'),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Open map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _callEmergency,
                icon: const Icon(Icons.call_rounded, size: 18),
                label: const Text('Call 0800 723 999'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacitySafe(0.08),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final fireCount =
        _facilities.where((facility) => facility.isFireStation).length;
    final medicalCount = _facilities.length - fireCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Nearby fire units',
              value: fireCount.toString(),
              icon: Icons.fire_truck_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Medical support',
              value: medicalCount.toString(),
              icon: Icons.local_hospital_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Map status',
              value: _loadingFacilities ? '...' : 'Live',
              icon: Icons.route_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick actions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.crisis_alert_rounded,
                  label: 'Report',
                  onTap: () => context.go('/report'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionTile(
                  icon: Icons.map_rounded,
                  label: 'Map',
                  onTap: () => context.go('/map'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.call_rounded,
                  label: 'Call',
                  onTap: _callEmergency,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About',
                  onTap: () => context.go('/about'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyFacilities(List<EmergencyFacility> facilities) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Nearest responders',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              Text(
                _loadingFacilities
                    ? 'Loading...'
                    : '${_facilities.length} found',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (facilities.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Nearby responders will appear here once the map service returns results.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...facilities.map(
              (facility) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FacilityCard(facility: facility),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({
    required this.loading,
    required this.label,
  });

  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: loading
            ? AppColors.tertiary.withOpacitySafe(0.12)
            : AppColors.success.withOpacitySafe(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            color: loading ? AppColors.tertiary : AppColors.success,
            size: 8,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: loading ? AppColors.tertiaryDark : AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacitySafe(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({required this.facility});

  final EmergencyFacility facility;

  @override
  Widget build(BuildContext context) {
    final color =
        facility.isFireStation ? AppColors.primary : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacitySafe(0.12),
              borderRadius: BorderRadius.circular(14),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  facility.typeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }
}
