import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'data/services/auth_provider.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/register_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/jobs_screen.dart';
import 'presentation/screens/job_detail_screen.dart';
import 'presentation/screens/earnings_screen.dart';
import 'presentation/screens/profile_screen.dart';
import 'presentation/widgets/bottom_nav.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  Animate.restartOnHotReload = true;
  runApp(const GkmGardenerApp());
}

class GkmGardenerApp extends StatelessWidget {
  const GkmGardenerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'GKM Gardener',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _RootGate(),
        onGenerateRoute: _generateRoute,
      ),
    );
  }

  static Route<dynamic> _generateRoute(RouteSettings settings) {
    Widget page;
    switch (settings.name) {
      case '/register':
        page = const RegisterScreen();
        break;
      default:
        if (settings.name?.startsWith('/job/') == true) {
          final id = int.tryParse(settings.name!.replaceFirst('/job/', '')) ?? 0;
          page = JobDetailScreen(jobId: id);
          // Use slide transition for job detail
          return PageRouteBuilder(
            settings: settings,
            transitionDuration: const Duration(milliseconds: 380),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, __, ___) => page,
            transitionsBuilder: (_, a, __, child) {
              final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
              return SlideTransition(
                position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(c),
                child: FadeTransition(opacity: Tween<double>(begin: 0.5, end: 1).animate(c), child: child));
            },
          );
        }
        page = const _RootGate();
    }

    return PageRouteBuilder(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: c,
          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(c),
            child: child));
      },
    );
  }
}

// ── ROOT GATE — decides auth vs app ─────────────────────────────────────────
class _RootGate extends StatelessWidget {
  const _RootGate();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) return const _SplashScreen();
    if (!auth.isAuthed)  return LoginScreen(onLoggedIn: () => _goHome(context));
    return const _HomeShell();
  }

  void _goHome(BuildContext ctx) {
    Navigator.pushAndRemoveUntil(ctx,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const _HomeShell(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }
}

// ── HOME SHELL ──────────────────────────────────────────────────────────────
class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override State<_HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<_HomeShell> {
  int _idx = 0;

  void _onLoggedOut() {
    context.read<AuthProvider>().logout().then((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const _RootGate(),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onJobsTap: () => setState(() => _idx = 1)),
      const JobsScreen(),
      const EarningsScreen(),
      ProfileScreen(onLoggedOut: _onLoggedOut),
    ];
    return Scaffold(
      body: IndexedStack(index: _idx, children: pages),
      bottomNavigationBar: GkmBottomNav(
        currentIndex: _idx,
        onTap: (i) { setState(() => _idx = i); },
      ),
    );
  }
}

// ── SPLASH ────────────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 1.5),
          ),
          child: const Icon(Icons.eco_rounded, color: AppColors.gold, size: 44),
        ).animate().scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1), curve: Curves.elasticOut, duration: 700.ms),
        const SizedBox(height: 22),
        Text('GKM Gardener',
          style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
        const SizedBox(height: 5),
        Text('Ghar Ka Mali',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white38),
        ).animate().fadeIn(delay: 400.ms, duration: 300.ms),
        const SizedBox(height: 48),
        SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold.withOpacity(0.5)),
        ).animate().fadeIn(delay: 600.ms),
      ])),
    );
  }
}
