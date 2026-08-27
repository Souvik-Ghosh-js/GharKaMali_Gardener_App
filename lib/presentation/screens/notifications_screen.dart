import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiService();
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.getNotifications();
      if (mounted) setState(() { _items = res; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load notifications'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        GradientHeader(
          bottomPadding: 20,
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: Colors.white70),
              ),
            ),
            Expanded(child: Text('Notifications',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
              ),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.forest,
            onRefresh: _load,
            child: _loading
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: 5,
                    itemBuilder: (_, __) => const SkeletonCard(),
                  )
                : _error != null
                    ? ListView(children: [const SizedBox(height: 60), EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Something went wrong',
                        subtitle: _error!,
                      )])
                    : _items.isEmpty
                        ? ListView(children: const [SizedBox(height: 60), EmptyState(
                            icon: Icons.notifications_off_outlined,
                            title: 'No notifications',
                            subtitle: 'Updates about jobs, leads and attendance will appear here.',
                          )])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final n = _items[i] is Map ? Map<String, dynamic>.from(_items[i] as Map) : <String, dynamic>{};
                              return _NotificationTile(n: n)
                                  .animate()
                                  .fadeIn(delay: Duration(milliseconds: i * 40), duration: 300.ms)
                                  .slideY(begin: 0.08, end: 0, delay: Duration(milliseconds: i * 40), duration: 300.ms);
                            },
                          ),
          ),
        ),
      ]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> n;
  const _NotificationTile({required this.n});

  IconData get _icon {
    final type = (n['type'] ?? '').toString();
    if (type.contains('lead')) return Icons.lightbulb_outline_rounded;
    if (type.contains('escalation') || type.contains('issue')) return Icons.report_problem_rounded;
    if (type.contains('attendance') || type.contains('leave')) return Icons.access_time_rounded;
    if (type.contains('payment') || type.contains('earning') || type.contains('payout')) return Icons.account_balance_wallet_rounded;
    if (type.contains('booking') || type.contains('job') || type.contains('assign')) return Icons.work_rounded;
    return Icons.notifications_rounded;
  }

  Color get _color {
    final type = (n['type'] ?? '').toString();
    if (type.contains('escalation') || type.contains('issue')) return AppColors.error;
    if (type.contains('lead')) return AppColors.goldDark;
    if (type.contains('payment') || type.contains('earning') || type.contains('payout')) return AppColors.success;
    if (type.contains('booking') || type.contains('job') || type.contains('assign')) return AppColors.info;
    return AppColors.forest;
  }

  String get _timeAgo {
    final raw = (n['created_at'] ?? n['createdAt'] ?? '').toString();
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final title = (n['title'] ?? 'Notification').toString();
    final body = (n['body'] ?? n['message'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon, size: 20, color: _color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(title,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
              const SizedBox(width: 8),
              Text(_timeAgo, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textFaint)),
            ]),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(body, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
            ],
          ])),
        ]),
      ),
    );
  }
}
