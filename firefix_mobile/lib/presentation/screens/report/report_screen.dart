import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/incident_model.dart';
import '../../../data/services/incident_service.dart';
import '../../../data/services/location_service.dart';
import '../../widgets/location_card.dart';
import '../../widgets/severity_picker.dart';
import '../../widgets/sos_button.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationService = LocationService();
  final _incidentService = IncidentService();

  String _severity = 'medium';
  String _address = '';
  Position? _position;
  bool _locationLoading = false;
  bool _submitting = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _locationLoading = true);
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
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  Future<void> _submitIncident() async {
    if (_position == null) {
      _showSnack('Wait for your location first');
      return;
    }

    setState(() => _submitting = true);

    final incident = IncidentModel(
      type: 'fire', // default; can be extended with a type picker
      description: _descriptionController.text.isEmpty
          ? 'Fire incident reported'
          : _descriptionController.text,
      severity: _severity,
      latitude: _position!.latitude,
      longitude: _position!.longitude,
      reportedBy: 'app',
    );

    try {
      final incidentId = await _incidentService.reportIncident(incident);
      if (!mounted) return;
      setState(() => _submitting = false);
      context.go('/confirmation/$incidentId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack('Could not send report. Check your connection and try again.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchLocation,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 18),
                _buildEmergencyPanel(),
                const SizedBox(height: 18),
                _buildFormPanel(),
                const SizedBox(height: 16),
                _buildFooterNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withOpacitySafe(0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacitySafe(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report emergency',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Capture the incident, confirm the location, and dispatch the response.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(
            icon: Icons.circle,
            label: _position == null ? 'GPS' : 'LIVE',
            color: _position == null ? AppColors.tertiary : AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacitySafe(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Immediate alert',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          SosButton(
            onPressed: () => setState(() => _expanded = true),
            isLoading: _submitting,
          ),
          const SizedBox(height: 12),
          Text(
            _expanded
                ? 'Review the details below before sending the report.'
                : 'Tap SOS to open the report form.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniAction(
                  icon: Icons.phone_rounded,
                  label: AppConstants.emergencyNumber,
                  onTap: () =>
                      _showSnack('Use the emergency call button on About'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniAction(
                  icon: Icons.location_on_rounded,
                  label: _locationLoading ? 'Locating...' : 'Refresh location',
                  onTap: _fetchLocation,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      child: !_expanded
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacitySafe(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(
                    icon: Icons.my_location_rounded,
                    title: 'Location',
                    subtitle: 'Confirm where the incident is happening.',
                  ),
                  const SizedBox(height: 10),
                  LocationCard(
                    address: _address,
                    isLoading: _locationLoading,
                    onRefresh: _fetchLocation,
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.local_fire_department_rounded,
                    title: 'Severity',
                    subtitle: 'Select the response intensity.',
                  ),
                  const SizedBox(height: 10),
                  SeverityPicker(
                    selected: _severity,
                    onSelect: (value) => setState(() => _severity = value),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.notes_rounded,
                    title: 'Incident notes',
                    subtitle: 'Add extra details if needed.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'Describe smoke, flames, casualties, access issues...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    icon: Icons.phone_rounded,
                    title: 'Contact number',
                    subtitle:
                        'Optional, used only if responders need to call back.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '07XXXXXXXX',
                      prefixIcon: Icon(Icons.phone_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitIncident,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _submitting ? 'Sending...' : 'Send report',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFooterNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacitySafe(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withOpacitySafe(0.14)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppColors.secondary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Keep the device on and stay clear of the fire. The map and dispatch flow will guide the nearest responders.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.secondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacitySafe(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacitySafe(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 8),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}