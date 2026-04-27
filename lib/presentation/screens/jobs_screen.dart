import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'job_detail_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override State<JobsScreen> createState() => _JobsScreenState();
}
class _JobsScreenState extends State<JobsScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tab;
  bool _loading = true;
  List<dynamic> _jobs = [];

  static const _filters = [
    _Filter('Today',    null,                          'today'),
    _Filter('Assigned', 'assigned',                    null),
    _Filter('Active',   'en_route,arrived,in_progress', null),
    _Filter('Done',     'completed',                   null),
  ];

  int _filterIdx = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _filters.length, vsync: this)
      ..addListener(() {
        if (!_tab.indexIsChanging) {
          setState(() { _filterIdx = _tab.index; _jobs = []; });
          _load();
        }
      });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = _filters[_filterIdx];
      final today = DateTime.now().toIso8601String().split('T')[0];
      final res = await _api.getJobs(
        status: f.status,
        date: f.dateMode == 'today' ? today : null,
      );

      final items = res is Map ? (res['items'] ?? res['data'] ?? []) : res;
      if (mounted) setState(() { _jobs = items is List ? items : []; _loading = false; });
    } catch (e) {

      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(child: GradientHeader(
            bottomPadding: 20,
            child: Row(children: [
              Expanded(child: Text('My Jobs', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white24)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text('Refresh', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                  ]),
                ),
              ),
            ]),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 15), // Add spacing from header
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: cardShadow(),
                  ),
                  child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(
                        color: AppColors.forest,
                        borderRadius: BorderRadius.circular(12)
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.textMuted,
                    dividerColor: Colors.transparent,
                    tabs: _filters.map((f) => Tab(text: f.label, height: 36)).toList(),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms)),        ],
        body: RefreshIndicator(
          color: AppColors.forest,
          onRefresh: _load,
          child: _loading
              ? ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                  itemBuilder: (_, __) => const SkeletonCard(),
                )
              : _jobs.isEmpty
                  ? ListView(children: [SizedBox(height: 60), EmptyState(
                      icon: Icons.work_off_outlined,
                      title: 'No jobs here',
                      subtitle: _filterIdx == 0 ? 'No jobs scheduled for today' : 'Nothing in this category',
                    )])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _jobs.length,
                      itemBuilder: (ctx, i) => _JobListCard(job: _jobs[i], index: i)
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: i * 60), duration: 350.ms)
                          .slideY(begin: 0.1, end: 0, delay: Duration(milliseconds: i * 60), duration: 350.ms, curve: Curves.easeOut),
                    ),
        ),
      ),
    );
  }
}

class _Filter {
  final String label;
  final String? status, dateMode;
  const _Filter(this.label, this.status, this.dateMode);
}

class _JobListCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final int index;
  const _JobListCard({required this.job, required this.index});

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'assigned';
    final isActive = ['en_route', 'arrived', 'in_progress'].contains(status);

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
        padding: const EdgeInsets.all(0),
        child: Column(children: [
          // Active indicator banner
          if (isActive) Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.warning)),
              const SizedBox(width: 6),
              Text('ACTIVE JOB', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.warning, letterSpacing: 1)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: isActive
                        ? [AppColors.warning, AppColors.warning.withOpacity(0.7)]
                        : [AppColors.forest, AppColors.forestMid]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(isActive ? Icons.directions_run_rounded : Icons.eco_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job['booking_number']?.toString() ?? '#${job['id']}',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text(job['customer']?['name'] ?? 'Customer',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
                ])),
                StatusBadge(status),
              ]),
              const SizedBox(height: 14),
              Container(height: 1, color: AppColors.borderLight),
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
                Text(job['scheduled_time'] ?? '—', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
                const Spacer(),
                const Icon(Icons.local_florist_rounded, size: 14, color: AppColors.textFaint),
                const SizedBox(width: 5),
                Text('${job['plant_count'] ?? '?'} plants', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 8),
                Text('View →', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.forest)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
