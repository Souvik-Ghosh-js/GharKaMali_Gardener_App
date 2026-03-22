import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final _api = ApiService();
  int _periodIdx = 2;
  static const _periods = ['daily', 'weekly', 'monthly'];
  Map<String, dynamic>? _earnings;
  List<dynamic> _rewards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getEarnings(_periods[_periodIdx]),
        _api.getRewards(),
      ]);
      if (!mounted) return;
      setState(() {
        _earnings = results[0] is Map<String,dynamic> ? results[0] as Map<String,dynamic> : {};

        final rewardsResponse = results[1] as Map<String, dynamic>;
        if (rewardsResponse.containsKey('items') && rewardsResponse['items'] is List) {
          _rewards = rewardsResponse['items'] as List;
        } else if (rewardsResponse.containsKey('rewards') && rewardsResponse['rewards'] is List) {
          _rewards = rewardsResponse['rewards'] as List;
        } else if (rewardsResponse.containsKey('data') && rewardsResponse['data'] is List) {
          _rewards = rewardsResponse['data'] as List;
        } else {
          _rewards = [];
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading earnings: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(int i) {
    setState(() {
      _periodIdx = i;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalEarnings = (_earnings?['total_earnings'] ?? _earnings?['totalEarnings'] ?? 0) as num;
    final totalJobs     = (_earnings?['total_jobs'] ?? _earnings?['completedJobs'] ?? 0) as num;
    final avgRating     = (_earnings?['avg_rating'] ?? 0) as num;
    final breakdown     = (_earnings?['breakdown'] ?? _earnings?['periods'] ?? []) as List;
    final totalRewards  = _rewards.where((r) => r['type'] == 'reward').fold<num>(0, (s, r) => s + ((r['amount'] as num?) ?? 0));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Hero Header
            SliverToBoxAdapter(
              child: GradientHeader(
                bottomPadding: 32,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EARNINGS',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white54,
                            letterSpacing: 1.5
                        )
                    ),
                    const SizedBox(height: 8),
                    _loading
                        ? const SkeletonBox(width: 160, height: 48, radius: 8)
                        : Text(
                      '₹${NumberFormat.decimalPattern('en_IN').format(totalEarnings)}',
                      style: GoogleFonts.poppins(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: AppColors.gold,
                        letterSpacing: -1.5,
                        height: 1,
                      ),
                    ).animate().fadeIn(duration: 400.ms).scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1, 1)
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '${_periods[_periodIdx]} period',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500
                        )
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _HeroStat(
                            label: 'Jobs Done',
                            value: '$totalJobs',
                            icon: Icons.check_circle_rounded,
                            color: Colors.white
                        ),
                        const SizedBox(width: 28),
                        _HeroStat(
                            label: 'Avg Rating',
                            value: avgRating > 0 ? avgRating.toStringAsFixed(1) : '—',
                            icon: Icons.star_rounded,
                            color: AppColors.gold
                        ),
                        const SizedBox(width: 28),
                        _HeroStat(
                            label: 'Rewards',
                            value: '+₹${NumberFormat.compact().format(totalRewards)}',
                            icon: Icons.emoji_events_rounded,
                            color: Colors.white
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Content with proper padding (no negative values)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Changed from -24 to 16
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Period Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: cardShadow(),
                    ),
                    child: Row(
                      children: List.generate(_periods.length, (i) {
                        final sel = i == _periodIdx;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _setPeriod(i),
                            child: AnimatedContainer(
                              duration: 200.ms,
                              curve: Curves.easeInOut,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? AppColors.forest : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _periods[i][0].toUpperCase() + _periods[i].substring(1),
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: sel ? Colors.white : AppColors.textMuted
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ).animate().fadeIn(duration: 300.ms),
                  const SizedBox(height: 14),

                  // Chart
                  _loading
                      ? const SkeletonBox(width: double.infinity, height: 220, radius: 20)
                      : breakdown.isEmpty
                      ? PremiumCard(
                      child: EmptyState(
                          icon: Icons.bar_chart_outlined,
                          title: 'No data',
                          subtitle: 'Complete jobs to see earnings'
                      )
                  )
                      : PremiumCard(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_periods[_periodIdx][0].toUpperCase()}${_periods[_periodIdx].substring(1)} Breakdown',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: breakdown.map((b) => (b['earnings'] ?? b['amount'] ?? 0) as num)
                                  .fold<num>(0, (a, b) => a > b ? a : b)
                                  .toDouble() * 1.2,
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                                    '₹${NumberFormat.compact().format(rod.toY)}',
                                    GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  tooltipRoundedRadius: 8,
                                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  tooltipMargin: 6,
                                  getTooltipColor: (_) => AppColors.forest,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    getTitlesWidget: (v, _) {
                                      final i = v.toInt();
                                      if (i < 0 || i >= breakdown.length) return const SizedBox();
                                      final b = breakdown[i];
                                      final lbl = (b['label'] ?? b['date'] ?? '$i').toString();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                            lbl.length > 6 ? lbl.substring(lbl.length - 5) : lbl,
                                            style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textMuted)
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderLight, strokeWidth: 1)
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: breakdown.asMap().entries.map((e) => BarChartGroupData(
                                x: e.key,
                                barRods: [BarChartRodData(
                                  toY: ((e.value['earnings'] ?? e.value['amount'] ?? 0) as num).toDouble(),
                                  color: AppColors.forest,
                                  width: breakdown.length > 0
                                      ? ((MediaQuery.of(context).size.width - 80) / breakdown.length - 6).clamp(6, 20)
                                      : 10,
                                  borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(6),
                                      topRight: Radius.circular(6)
                                  ),
                                  backDrawRodData: BackgroundBarChartRodData(
                                      show: true,
                                      toY: 100,
                                      color: AppColors.bgSubtle
                                  ),
                                )],
                              )).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 14),

                  // Breakdown List
                  if (!_loading && breakdown.isNotEmpty) ...[
                    PremiumCard(
                      padding: const EdgeInsets.all(0),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                            child: SectionHeader(title: 'Period Detail'),
                          ),
                          ...breakdown.take(8).toList().asMap().entries.map((e) {
                            final b = e.value;
                            return Container(
                              key: ValueKey('breakdown_${e.key}'), // Add key
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              decoration: BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: AppColors.borderLight,
                                          width: e.key == breakdown.take(8).length - 1 ? 0 : 1
                                      )
                                  )
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (b['label'] ?? b['date'] ?? '—').toString(),
                                          style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.text
                                          ),
                                        ),
                                        Text(
                                            '${b['jobs'] ?? b['total_jobs'] ?? 0} jobs',
                                            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₹${NumberFormat.decimalPattern('en_IN').format(b['earnings'] ?? b['amount'] ?? 0)}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.forest
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 14),
                  ],

                  // Rewards List
                  if (_rewards.isNotEmpty) ...[
                    const SectionHeader(title: 'Rewards & Penalties'),
                    const SizedBox(height: 12),
                    PremiumCard(
                      padding: const EdgeInsets.all(0),
                      child: Column(
                        children: _rewards.take(10).toList().asMap().entries.map((e) {
                          final r = e.value;
                          final isReward = r['type'] == 'reward';
                          final isLast = e.key == _rewards.take(10).length - 1;
                          return Container(
                            key: ValueKey('reward_${r['id'] ?? e.key}'), // Add unique key
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: AppColors.borderLight,
                                        width: isLast ? 0 : 1
                                    )
                                )
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isReward
                                        ? AppColors.success.withOpacity(0.1)
                                        : AppColors.error.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                      isReward ? Icons.emoji_events_rounded : Icons.warning_rounded,
                                      size: 20,
                                      color: isReward ? AppColors.success : AppColors.error
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          r['reason']?.toString() ?? '—',
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.text2
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis
                                      ),
                                      if (r['created_at'] != null)
                                        Text(
                                            r['created_at'].toString().split('T')[0],
                                            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textFaint)
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isReward ? '+' : '−'}₹${r['amount'] ?? 0}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: isReward ? AppColors.success : AppColors.error
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _HeroStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
      Text(
          label,
          style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.white38,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3
          )
      ),
    ],
  );
}