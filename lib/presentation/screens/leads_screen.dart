import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Human-readable labels for the lead types accepted by the backend.
const Map<String, String> kLeadTypeLabels = {
  'repotting': 'Repotting',
  'new_plants': 'New Plants',
  'pots': 'Pots',
  'vermicompost': 'Vermicompost',
  'pest_control': 'Pest Control',
  'lawn_service': 'Lawn Service',
  'balcony_makeover': 'Balcony Makeover',
  'terrace_garden': 'Terrace Garden',
  'plant_replacement': 'Plant Replacement',
  'other': 'Other',
};

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final _api = ApiService();
  List<dynamic> _leads = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.getLeads();
      if (mounted) setState(() { _leads = res; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load leads'; _loading = false; });
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
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My Leads', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Services you suggested to customers',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white60)),
            ])),
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
                    itemCount: 4,
                    itemBuilder: (_, __) => const SkeletonCard(),
                  )
                : _error != null
                    ? ListView(children: [const SizedBox(height: 60), EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Something went wrong',
                        subtitle: _error!,
                      )])
                    : _leads.isEmpty
                        ? ListView(children: const [SizedBox(height: 60), EmptyState(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'No leads yet',
                            subtitle: 'Suggest a service from an active job to earn rewards on conversions.',
                          )])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            itemCount: _leads.length,
                            itemBuilder: (_, i) {
                              final l = _leads[i] is Map ? Map<String, dynamic>.from(_leads[i] as Map) : <String, dynamic>{};
                              return _LeadCard(lead: l)
                                  .animate()
                                  .fadeIn(delay: Duration(milliseconds: i * 50), duration: 300.ms)
                                  .slideY(begin: 0.08, end: 0, delay: Duration(milliseconds: i * 50), duration: 300.ms);
                            },
                          ),
          ),
        ),
      ]),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Map<String, dynamic> lead;
  const _LeadCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    final status = (lead['status'] ?? 'pending').toString();
    final type = (lead['type'] ?? '').toString();
    final typeLabel = kLeadTypeLabels[type] ?? (type.isEmpty ? 'Lead' : type.replaceAll('_', ' '));
    final note = (lead['note'] ?? '').toString();
    final bookingNo = lead['booking']?['booking_number']?.toString()
        ?? (lead['booking_id'] != null ? '#${lead['booking_id']}' : null);
    final createdRaw = (lead['created_at'] ?? lead['createdAt'] ?? '').toString();
    final created = DateTime.tryParse(createdRaw)?.toLocal();
    final dateLabel = created != null ? '${created.day} ${_mo(created.month)} ${created.year}' : '';

    final Color color;
    switch (status) {
      case 'approved': color = AppColors.success; break;
      case 'rejected': color = AppColors.error; break;
      case 'converted': color = AppColors.info; break;
      default: color = AppColors.warning;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.goldDark.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.goldDark),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(typeLabel, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              if (bookingNo != null || dateLabel.isNotEmpty)
                Text([if (bookingNo != null) bookingNo, if (dateLabel.isNotEmpty) dateLabel].join(' • '),
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
              child: Text(status.toUpperCase(),
                  style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
            ),
          ]),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.bgSubtle, borderRadius: BorderRadius.circular(10)),
              child: Text(note, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.text2, height: 1.4)),
            ),
          ],
        ]),
      ),
    );
  }

  String _mo(int m) => ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}
