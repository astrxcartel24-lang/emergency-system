import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'presentation/screens/about/about_screen.dart';
import 'presentation/screens/confirmation/confirmation_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/map/map_screen.dart';
import 'presentation/screens/report/report_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: KaradaApp()));
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(
        location: state.uri.toString(),
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/report',
          builder: (context, state) => const ReportScreen(),
        ),
        GoRoute(
          path: '/map',
          builder: (context, state) => const MapScreen(),
        ),
        GoRoute(
          path: '/about',
          builder: (context, state) => const AboutScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/confirmation/:incidentId',
      builder: (context, state) => ConfirmationScreen(
        incidentId: state.pathParameters['incidentId'] ?? '',
      ),
    ),
  ],
);

class KaradaApp extends StatelessWidget {
  const KaradaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Karada',
      theme: AppTheme.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  int _locationIndex() {
    if (location.startsWith('/report')) return 1;
    if (location.startsWith('/map')) return 2;
    if (location.startsWith('/about')) return 3;
    return 0;
  }

  void _navigate(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/report');
        break;
      case 2:
        context.go('/map');
        break;
      case 3:
        context.go('/about');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _locationIndex();
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.white.withOpacitySafe(0.98),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacitySafe(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Colors.transparent,
                indicatorColor: AppColors.primary.withOpacitySafe(0.12),
                indicatorShape: const StadiumBorder(),
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    fontSize: 11,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: states.contains(WidgetState.selected)
                        ? AppColors.primary
                        : AppColors.muted,
                  ),
                ),
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? AppColors.primary
                        : AppColors.muted,
                    size: 24,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: index,
                height: 68,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: (value) => _navigate(context, value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.crisis_alert_rounded),
                    label: 'Report',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_rounded),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.info_outline_rounded),
                    label: 'About',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
