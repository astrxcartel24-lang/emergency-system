import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class ConfirmationScreen extends StatefulWidget {
  final String incidentId;
  const ConfirmationScreen({super.key, required this.incidentId});

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _checkController;
  late final AnimationController _pulseController;
  late final Animation<double> _checkAnim;
  late final Animation<double> _pulseAnim;
  int _eta = 8;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _checkAnim = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkController.forward();
    _countDown();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _countDown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_eta > 1) {
        setState(() => _eta--);
        _countDown();
      }
    });
  }

  String get _shortId {
    final id = widget.incidentId;
    return id.length >= 6 ? id.substring(id.length - 6) : id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
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
              _buildEtaCard(),
              const SizedBox(height: 18),
              _buildTimelineCard(),
              const SizedBox(height: 18),
              _buildSafetyCard(),
              const SizedBox(height: 18),
              _buildActions(context),
            ],
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
            color: AppColors.dark.withOpacitySafe(0.14),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _checkAnim,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withOpacitySafe(0.14),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 34,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report sent',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'The dispatcher has your report and the response is moving.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          _MiniBadge(
            color: AppColors.tertiary,
            text: 'ID #$_shortId',
          ),
        ],
      ),
    );
  }

  Widget _buildEtaCard() {
    return ScaleTransition(
      scale: _pulseAnim,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacitySafe(0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              'ESTIMATED ARRIVAL',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '~$_eta min',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 54,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fire_truck_rounded,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Nearest responders are being routed now',
                  style: TextStyle(
                    color: Colors.white.withOpacitySafe(0.8),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dispatch status',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 14),
          _statusRow(
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            title: 'Incident received',
            body: 'The report has been logged and validated.',
            done: true,
          ),
          _statusRow(
            icon: Icons.radio_button_checked_rounded,
            color: AppColors.tertiary,
            title: 'Dispatcher triage',
            body: 'Severity and location are being assessed.',
            done: true,
          ),
          _statusRow(
            icon: Icons.circle_outlined,
            color: AppColors.muted,
            title: 'Responder en route',
            body: 'The nearest fire or medical unit is being guided in.',
            done: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withOpacitySafe(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.tertiary.withOpacitySafe(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.tertiaryDark),
              SizedBox(width: 8),
              Text(
                'Safety guidance',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...[
            'Move away from smoke and heat.',
            'Stay visible and wait in a safe place.',
            'Keep routes to the building clear.',
            'Share access details with responders if needed.',
          ].map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.tertiaryDark,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        color: AppColors.dark,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.go('/report'),
            icon: const Icon(Icons.add_alert_rounded, size: 18),
            label: const Text('New report'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go('/map'),
            icon: const Icon(Icons.map_rounded, size: 18),
            label: const Text('Open map'),
          ),
        ),
      ],
    );
  }

  Widget _statusRow({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required bool done,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacitySafe(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacitySafe(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
