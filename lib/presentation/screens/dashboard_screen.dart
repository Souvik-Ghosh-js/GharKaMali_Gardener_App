import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'attendance_screen.dart';
import 'job_detail_screen.dart';
import 'leads_screen.dart';
import 'notifications_screen.dart';

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

  // Status buckets (computed from getJobs)
  int _cAssigned = 0, _cActive = 0, _cDoneToday = 0, _cUpcoming = 0;

  // Attendance
  Map<String, dynamic>? _attToday;
  bool _attLoading = true, _attActing = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() { _loadingJobs = true; _loadingEarnings = true; _attLoading = true; });
    await Future.wait([_loadJobs(), _loadEarnings(), _loadAttendance()]);
  }

  Future<void> _loadJobs() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final res = await _api.getJobs(limit: 100);
      final items = res is Map ? (res['items'] ?? res['data'] ?? []) : res;
      final all = items is List ? items : <dynamic>[];

      int assigned = 0, active = 0, doneToday = 0, upcoming = 0;
      final todayList = <dynamic>[];
      for (final j in all) {
        if (j is! Map) continue;
        final status = j['status']?.toString() ?? '';
        final date = (j['scheduled_date'] ?? '').toString().split('T')[0];
        final isToday = date == today;
        final isFuture = date.compareTo(today) > 0;
        if (['en_route', 'arrived', 'in_progress'].contains(status)) {
          active++;
        } else if (status == 'assigned' && isFuture) {
          upcoming++;
        } else if (status == 'assigned') {
          assigned++;
        } else if (status == 'completed' && isToday) {
          doneToday++;
        }
        if (isToday && !['cancelled', 'failed'].contains(status)) todayList.add(j);
      }

      if (mounted) setState(() {
        _todayJobs = todayList;
        _cAssigned = assigned; _cActive = active; _cDoneToday = doneToday; _cUpcoming = upcoming;
        _loadingJobs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingJobs = false);
    }
  }

  Future<void> _loadEarnings() async {
    try {
      final res = await _api.getEarnings('weekly');
      if (mounted) setState(() { _earnings = res is Map<String,dynamic> ? res : {}; _loadingEarnings = false; });
    } catch (_) { if (mounted) setState(() => _loadingEarnings = false); }
  }

  // ── ATTENDANCE ────────────────────────────────────────────────────────────
  Future<void> _loadAttendance() async {
    try {
      final res = await _api.getAttendanceToday();
      if (mounted) setState(() { _attToday = res is Map<String,dynamic> ? res : null; _attLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _attLoading = false);
    }
  }

  /// Today's attendance row, or null when not checked in yet.
  Map<String, dynamic>? get _attRow {
    var a = _attToday;
    if (a == null) return null;
    if (a['attendance'] is Map) a = Map<String, dynamic>.from(a['attendance'] as Map);
    final hasIn = a['check_in_time'] != null || a['check_in'] != null ||
        a['checkin_time'] != null || a['check_in_at'] != null;
    return hasIn ? a : null;
  }

  Future<Position?> _currentPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator
          .getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkIn() async {
    setState(() => _attActing = true);
    HapticFeedback.mediumImpact();
    final pos = await _currentPosition(); // graceful: null when denied/unavailable
    try {
      await _api.attendanceCheckIn(latitude: pos?.latitude, longitude: pos?.longitude);
      if (mounted) showAppToast(context, 'Checked in. Have a great day!', isSuccess: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppToast(context, 'Check-in failed. Please try again.', isError: true);
    } finally {
      if (mounted) { setState(() => _attActing = false); _loadAttendance(); }
    }
  }

  Future<void> _checkOut() async {
    setState(() => _attActing = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.attendanceCheckOut();
      if (mounted) showAppToast(context, 'Checked out. See you tomorrow!', isSuccess: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppToast(context, 'Check-out failed. Please try again.', isError: true);
    } finally {
      if (mounted) { setState(() => _attActing = false); _loadAttendance(); }
    }
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

  void _push(Widget page) {
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(cv),
          child: FadeTransition(opacity: Tween<double>(begin: 0.4, end: 1).animate(cv), child: child));
      }));
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
    final avgRating   = _toNum(gp['rating'] ?? gp['avg_rating']);

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
                // Notifications bell
                GestureDetector(
                  onTap: () => _push(const NotificationsScreen()),
                  child: Container(
                    width: 38, height: 38,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: const Icon(Icons.notifications_none_rounded, size: 20, color: Colors.white70),
                  ),
                ).animate().fadeIn(delay: 150.ms),
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
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _StatMini(label: 'Weekly', value: '₹${(weeklyTotal).toStringAsFixed(0)}', icon: Icons.account_balance_wallet_rounded, color: AppColors.gold, dark: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatMini(label: 'Jobs Today', value: '${_todayJobs.length}', icon: Icons.check_circle_rounded, color: AppColors.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatMini(label: 'Rating', value: avgRating > 0 ? avgRating.toStringAsFixed(1) : 'New', icon: Icons.star_rounded, color: const Color(0xFFD4B96A))),
                ]),
                const SizedBox(height: 12),
                // Status buckets
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: cardShadow(),
                  ),
                  child: Row(children: [
                    Expanded(child: _BucketStat(label: 'Assigned', count: _cAssigned, color: AppColors.info, loading: _loadingJobs)),
                    _bucketDivider(),
                    Expanded(child: _BucketStat(label: 'In Progress', count: _cActive, color: AppColors.warning, loading: _loadingJobs)),
                    _bucketDivider(),
                    Expanded(child: _BucketStat(label: 'Done Today', count: _cDoneToday, color: AppColors.success, loading: _loadingJobs)),
                    _bucketDivider(),
                    Expanded(child: _BucketStat(label: 'Upcoming', count: _cUpcoming, color: AppColors.textMuted, loading: _loadingJobs)),
                  ]),
                ),
                const SizedBox(height: 12),
                _buildAttendanceCard(),
                const SizedBox(height: 12),
                // My Leads quick action
                PremiumCard(
                  onTap: () => _push(const LeadsScreen()),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: AppColors.goldDark.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.goldDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('My Leads', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                      Text('Track your service suggestions', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textFaint),
                  ]),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ).animate().slideY(begin: 0.3, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(duration: 400.ms)),

          // ── TODAY'S JOBS ─────────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SectionHeader(
              title: "Today's Jobs",
              action: _todayJobs.isNotEmpty ? 'View all' : null,
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
          else if (_todayJobs.isEmpty)
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
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final job = _todayJobs[i];
                return _JobCard(job: job, index: i)
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: i * 80), duration: 400.ms)
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      delay: Duration(milliseconds: i * 80),
                      duration: 400.ms,
                      curve: Curves.easeOut,
                    );
              },
              childCount: _todayJobs.length,
            ),
          ),


          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
      ),
    );
  }

  Widget _bucketDivider() => Container(width: 1, height: 34, color: AppColors.borderLight);

  // ── ATTENDANCE CARD ────────────────────────────────────────────────────────
  Widget _buildAttendanceCard() {
    final row = _attRow;
    final rawIn  = row?['check_in_time'] ?? row?['check_in'] ?? row?['checkin_time'] ?? row?['check_in_at'];
    final rawOut = row?['check_out_time'] ?? row?['check_out'] ?? row?['checkout_time'] ?? row?['check_out_at'];
    final checkedIn = row != null;
    final checkedOut = checkedIn && rawOut != null;

    String fmtTime(dynamic raw) {
      if (raw == null) return '—';
      final s = raw.toString();
      final d = DateTime.tryParse(s)?.toLocal();
      if (d != null) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      if (s.length >= 5 && s.contains(':')) return s.substring(0, 5);
      return s;
    }

    String hoursLabel() {
      final h = row?['total_hours'] ?? row?['hours'];
      if (h != null) return '${(num.tryParse(h.toString()) ?? 0).toStringAsFixed(1)}h';
      final din = DateTime.tryParse(rawIn?.toString() ?? '')?.toLocal();
      final dout = DateTime.tryParse(rawOut?.toString() ?? '')?.toLocal();
      if (din != null && dout != null) {
        final mins = dout.difference(din).inMinutes;
        return '${(mins / 60).toStringAsFixed(1)}h';
      }
      return '';
    }

    final String title;
    final String subtitle;
    final Color accent;
    if (_attLoading) {
      title = 'Attendance'; subtitle = 'Loading…'; accent = AppColors.textMuted;
    } else if (!checkedIn) {
      title = 'Not checked in'; subtitle = 'Check in when you start your day'; accent = AppColors.warning;
    } else if (!checkedOut) {
      title = 'Checked in at ${fmtTime(rawIn)}'; subtitle = 'On duty — check out when you finish'; accent = AppColors.success;
    } else {
      final h = hoursLabel();
      title = 'Checked out${h.isNotEmpty ? ', $h' : ''}';
      subtitle = '${fmtTime(rawIn)} → ${fmtTime(rawOut)} • Done for today'; accent = AppColors.forest;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: cardShadow(),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('ATTENDANCE', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1)),
          const Spacer(),
          GestureDetector(
            onTap: () => _push(const AttendanceScreen()),
            child: Text('View history', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.forest)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(
              !checkedIn ? Icons.timer_outlined : (checkedOut ? Icons.check_circle_rounded : Icons.timer_rounded),
              size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
          ])),
          if (!_attLoading && !checkedOut)
            SizedBox(
              width: 110, height: 38,
              child: GkmButton(
                label: checkedIn ? 'Check Out' : 'Check In',
                icon: checkedIn ? Icons.logout_rounded : Icons.login_rounded,
                loading: _attActing,
                height: 38,
                color: checkedIn ? AppColors.warning : AppColors.forest,
                onTap: checkedIn ? _checkOut : _checkIn,
              ),
            ),
        ]),
      ]),
    );
  }
}

// ── BUCKET STAT ─────────────────────────────────────────────────────────────
class _BucketStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool loading;
  const _BucketStat({required this.label, required this.count, required this.color, required this.loading});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(loading ? '…' : '$count',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
    ]);
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
