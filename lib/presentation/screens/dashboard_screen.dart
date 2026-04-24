import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'job_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onJobsTap;
  const DashboardScreen({super.key, this.onJobsTap});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  List<dynamic> _todayJobs = [];
  Map<String, dynamic>? _earnings;
  bool _loadingJobs = true, _loadingEarnings = true, _togglingAvail = false;
  String? _error;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() { _loadingJobs = true; _loadingEarnings = true; _error = null; });
    await Future.wait([_loadJobs(), _loadEarnings()]);
  }

  Future<void> _loadJobs() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final res = await _api.getJobs(date: today, limit: 10);
      if (kDebugMode) print('🔍 [_loadJobs] Raw res type: ${res.runtimeType} | res: $res');
      final items = res is Map ? (res['items'] ?? res['data'] ?? []) : res;
      if (kDebugMode) print('🔍 [_loadJobs] Parsed items: $items');
      if (mounted) setState(() { _todayJobs = items is List ? items : []; _loadingJobs = false; });
    } catch (e) { 
      if (kDebugMode) print('❌ [_loadJobs] Error: $e');
      if (mounted) setState(() => _loadingJobs = false); 
    }
  }

  Future<void> _loadEarnings() async {
    try {
      final res = await _api.getEarnings('weekly');
      if (mounted) setState(() { _earnings = res is Map<String,dynamic> ? res : {}; _loadingEarnings = false; });
    } catch (_) { if (mounted) setState(() => _loadingEarnings = false); }
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _togglingAvail = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.setAvailability(val);
      final auth = context.read<AuthProvider>();
      final gp = Map<String, dynamic>.from(auth.user?['gardenerProfile'] ?? {});
      gp['is_available'] = val;
      await auth.updateUser({'gardenerProfile': gp});
      if (mounted) showAppToast(context, val ? 'You are now Online' : 'You went Offline', isSuccess: val);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _togglingAvail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final gp = user?['gardenerProfile'] as Map<String, dynamic>? ?? {};
    final isAvailable = gp['is_available'] == true;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final totals = _earnings?['totals'] as Map<String, dynamic>?;
    num _toNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }
    final weeklyTotal = _toNum(totals?['total_earnings']);
    final weeklyJobs  = _toNum(totals?['total_jobs']);
    final avgRating   = _toNum(gp['rating'] ?? gp['avg_rating']);
    final activeJobs  = _todayJobs; // Show all jobs for today regardless of status for debugging
    if (kDebugMode) print('🔍 [Dashboard] todayJobs: ${_todayJobs.length} | activeJobs: ${activeJobs.length}');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [
          // ── HEADER ──────────────────────────────────────────────────────
          SliverToBoxAdapter(child: GradientHeader(
            bottomPadding: 10,
            child: Column(children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white60)).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 2),
                  Text(user?['name'] ?? 'Gardener',
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                  ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1, end: 0),
                ])),
                // Availability toggle
                GestureDetector(
                  onTap: _togglingAvail ? null : () => _toggleAvailability(!isAvailable),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isAvailable ? AppColors.gold.withOpacity(0.15) : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: isAvailable ? AppColors.gold.withOpacity(0.4) : Colors.white.withOpacity(0.15)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_togglingAvail)
                        const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold))
                      else
                        AnimatedContainer(
                          duration: 300.ms, width: 8, height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isAvailable ? AppColors.gold : Colors.white38),
                        ),
                      const SizedBox(width: 7),
                      Text(isAvailable ? 'Online' : 'Offline',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700,
                          color: isAvailable ? AppColors.gold : Colors.white54)),
                    ]),
                  ),
                ).animate().fadeIn(delay: 200.ms),
              ]),
            ]),
          )),

          // ── STATS CARDS ─────────────────────────────────────────────────
// Replace the stats cards section (around line 130-140)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 20), // Add spacing from header
                Row(children: [
                  Expanded(child: _StatMini(label: 'Weekly', value: '₹${(weeklyTotal).toStringAsFixed(0)}', icon: Icons.account_balance_wallet_rounded, color: AppColors.gold, dark: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatMini(label: 'Jobs Today', value: '$weeklyJobs', icon: Icons.check_circle_rounded, color: AppColors.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatMini(label: 'Rating', value: avgRating > 0 ? avgRating.toStringAsFixed(1) : 'New', icon: Icons.star_rounded, color: const Color(0xFFD4B96A))),
                ]),
                const SizedBox(height: 20), // Add spacing
              ],
            ),
          ).animate().slideY(begin: 0.3, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(duration: 400.ms)),
          // ── TODAY'S JOBS ─────────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SectionHeader(
              title: "Today's Jobs",
              action: activeJobs.isNotEmpty ? 'View all' : null,
              onAction: widget.onJobsTap,
            ),
          )),

          if (_loadingJobs)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => const SkeletonCard(), childCount: 3,
              )),
            )
          else if (activeJobs.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PremiumCard(
                child: EmptyState(
                  icon: Icons.work_off_outlined,
                  title: 'No jobs today',
                  subtitle: isAvailable ? 'You\'re online. New jobs will appear here.' : 'Go online to receive jobs.',
                ),
              ),
            ))
          else
          SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
                final job = activeJobs[i];
                return _JobCard(job: job, index: i).animate()
                    .fadeIn(delay: Duration(milliseconds: i * 80), duration: 400.ms)
                    .slideY(begin: 0.15, end: 0, delay: Duration(milliseconds: i * 80), duration: 400.ms, curve: Curves.easeOut);
              }, childCount: activeJobs.length),


          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
      ),
    );
  }
}

// ── STAT MINI CARD ─────────────────────────────────────────────────────────
class _StatMini extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool dark;
  const _StatMini({required this.label, required this.value, required this.icon, required this.color, this.dark = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? AppColors.forest : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? Colors.transparent : AppColors.border),
        boxShadow: cardShadow(),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: dark ? color : color),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900, color: dark ? Colors.white : AppColors.text, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: dark ? Colors.white54 : AppColors.textMuted)),
      ]),
    );
  }
}

// ── JOB CARD ────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final int index;
  const _JobCard({required this.job, required this.index});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) print('🎨 [_JobCard] Building card for ${job['id']} | status: ${job['status']}');
    final status = job['status'] as String? ?? 'assigned';
    final date = job['scheduled_date'];
    final d = date != null ? DateTime.tryParse(date) : null;
    final formatted = d != null
        ? '${_weekday(d.weekday)}, ${d.day} ${_month(d.month)}'
        : 'Today';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        onTap: () => Navigator.push(context, PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 380),
                  reverseTransitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) => JobDetailScreen(jobId: int.tryParse(job['id'].toString()) ?? 0),
                  transitionsBuilder: (_, a, __, child) {
                    final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
                    return SlideTransition(
                      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(cv),
                      child: FadeTransition(opacity: Tween<double>(begin: 0.4, end: 1).animate(cv), child: child));
                  })),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.forest, AppColors.forestMid]),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.eco_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job['booking_number']?.toString() ?? '#${job['id']}',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(job['customer']?['name'] ?? 'Customer',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            ])),
            StatusBadge(status),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 5),
            Expanded(child: Text(job['service_address'] ?? '—',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 5),
            Text(job['scheduled_time'] ?? formatted,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(width: 12),
            const Icon(Icons.local_florist_rounded, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 5),
            Text('${job['plant_count'] ?? '?'} plants',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ]),
      ),
    );
  }

  String _weekday(int d) => ['', 'Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d];
  String _month(int m)   => ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
