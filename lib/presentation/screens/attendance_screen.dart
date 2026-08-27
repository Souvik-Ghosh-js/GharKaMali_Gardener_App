import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tab;

  // Attendance tab
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _monthData;
  bool _loadingMonth = true;

  // Leaves tab
  List<dynamic> _leaves = [];
  bool _loadingLeaves = true;

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _monthLabel => '${_monthName(_month.month)} ${_month.year}';

  static String _monthName(int m) =>
      ['', 'January','February','March','April','May','June','July','August','September','October','November','December'][m];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadMonth();
    _loadLeaves();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadMonth() async {
    setState(() => _loadingMonth = true);
    try {
      final res = await _api.getAttendanceMonth(_monthKey);
      if (mounted) setState(() { _monthData = res; _loadingMonth = false; });
    } on ApiException catch (e) {
      if (mounted) { setState(() { _monthData = null; _loadingMonth = false; }); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) setState(() { _monthData = null; _loadingMonth = false; });
    }
  }

  Future<void> _loadLeaves() async {
    setState(() => _loadingLeaves = true);
    try {
      final res = await _api.getLeaves();
      if (mounted) setState(() { _leaves = res; _loadingLeaves = false; });
    } on ApiException catch (e) {
      if (mounted) { setState(() => _loadingLeaves = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) setState(() => _loadingLeaves = false);
    }
  }

  void _changeMonth(int delta) {
    final now = DateTime.now();
    final next = DateTime(_month.year, _month.month + delta);
    // Don't go into the future beyond the current month
    if (next.year > now.year || (next.year == now.year && next.month > now.month)) return;
    setState(() => _month = next);
    _loadMonth();
  }

  Future<void> _openLeaveForm() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LeaveRequestSheet(),
    );
    if (submitted == true && mounted) {
      showAppToast(context, 'Leave request submitted', isSuccess: true);
      _loadLeaves();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        GradientHeader(
          bottomPadding: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: Colors.white70),
                ),
              ),
              Expanded(child: Text('Attendance',
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: cardShadow(),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'History', height: 36), Tab(text: 'Leaves', height: 36)],
            ),
          ),
        ).animate().fadeIn(duration: 300.ms),
        Expanded(child: TabBarView(controller: _tab, children: [
          _buildHistoryTab(),
          _buildLeavesTab(),
        ])),
      ]),
    );
  }

  // ── HISTORY TAB ───────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    final rows = (_monthData?['rows'] as List?) ?? [];
    final summary = _monthData?['summary'] as Map? ?? {};
    final daysPresent = (summary['days_present'] ?? rows.length).toString();
    final totalHoursRaw = summary['total_hours'];
    final totalHours = totalHoursRaw == null ? '—'
        : '${(num.tryParse(totalHoursRaw.toString()) ?? 0).toStringAsFixed(1)}h';

    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: _loadMonth,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Month selector
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _MonthBtn(icon: Icons.chevron_left_rounded, onTap: () => _changeMonth(-1)),
            Text(_monthLabel, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            _MonthBtn(icon: Icons.chevron_right_rounded, onTap: () => _changeMonth(1)),
          ]),
          const SizedBox(height: 14),
          // Summary
          Row(children: [
            Expanded(child: _SummaryBox(label: 'Days Present', value: _loadingMonth ? '…' : daysPresent, icon: Icons.event_available_rounded, color: AppColors.success)),
            const SizedBox(width: 10),
            Expanded(child: _SummaryBox(label: 'Total Hours', value: _loadingMonth ? '…' : totalHours, icon: Icons.timer_rounded, color: AppColors.info)),
          ]).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 18),
          if (_loadingMonth)
            ...List.generate(4, (_) => const SkeletonCard())
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: EmptyState(
                icon: Icons.event_busy_rounded,
                title: 'No attendance records',
                subtitle: 'Check-ins for this month will appear here.',
              ),
            )
          else
            ...rows.asMap().entries.map((e) {
              final r = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{};
              return _AttendanceRow(row: r)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: e.key * 40), duration: 300.ms);
            }),
        ],
      ),
    );
  }

  // ── LEAVES TAB ────────────────────────────────────────────────────────────
  Widget _buildLeavesTab() {
    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: _loadLeaves,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          GkmButton(label: 'Request Leave', icon: Icons.event_note_rounded, onTap: _openLeaveForm),
          const SizedBox(height: 18),
          Text('MY REQUESTS', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 10),
          if (_loadingLeaves)
            ...List.generate(3, (_) => const SkeletonCard())
          else if (_leaves.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: EmptyState(
                icon: Icons.beach_access_rounded,
                title: 'No leave requests',
                subtitle: 'Your leave requests and their status will appear here.',
              ),
            )
          else
            ..._leaves.asMap().entries.map((e) {
              final l = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{};
              return _LeaveRow(leave: l)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: e.key * 40), duration: 300.ms);
            }),
        ],
      ),
    );
  }
}

// ── SMALL WIDGETS ────────────────────────────────────────────────────────────
class _MonthBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MonthBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 20, color: AppColors.forest),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SummaryBox({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: cardShadow(),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AttendanceRow({required this.row});

  String _fmtTime(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString();
    final d = DateTime.tryParse(s)?.toLocal();
    if (d != null) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    // Plain "HH:mm:ss" strings
    if (s.length >= 5 && s.contains(':')) return s.substring(0, 5);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final dateRaw = (row['date'] ?? row['attendance_date'] ?? '').toString();
    final d = DateTime.tryParse(dateRaw);
    final dateLabel = d != null ? '${_wd(d.weekday)}, ${d.day} ${_mo(d.month)}' : dateRaw;
    final checkIn = _fmtTime(row['check_in_time'] ?? row['check_in'] ?? row['checkin_time']);
    final checkOut = _fmtTime(row['check_out_time'] ?? row['check_out'] ?? row['checkout_time']);
    final hoursRaw = row['total_hours'] ?? row['hours'];
    final hours = hoursRaw != null ? '${(num.tryParse(hoursRaw.toString()) ?? 0).toStringAsFixed(1)}h' : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.event_available_rounded, size: 18, color: AppColors.success),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dateLabel, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 2),
          Text('$checkIn  →  $checkOut', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
        ])),
        if (hours != null)
          Text(hours, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.forest)),
      ]),
    );
  }

  String _wd(int d) => ['', 'Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d];
  String _mo(int m) => ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}

class _LeaveRow extends StatelessWidget {
  final Map<String, dynamic> leave;
  const _LeaveRow({required this.leave});

  @override
  Widget build(BuildContext context) {
    final status = (leave['status'] ?? 'pending').toString();
    final from = (leave['from_date'] ?? '').toString().split('T')[0];
    final to = (leave['to_date'] ?? '').toString().split('T')[0];
    final reason = (leave['reason'] ?? '').toString();
    final Color color;
    switch (status) {
      case 'approved': color = AppColors.success; break;
      case 'rejected': color = AppColors.error; break;
      default: color = AppColors.warning;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_note_rounded, size: 16, color: AppColors.forest),
          const SizedBox(width: 8),
          Expanded(child: Text('$from → $to',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
            child: Text(status.toUpperCase(),
                style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
          ),
        ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(reason, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
        ],
      ]),
    );
  }
}

// ── LEAVE REQUEST SHEET ──────────────────────────────────────────────────────
class _LeaveRequestSheet extends StatefulWidget {
  const _LeaveRequestSheet();
  @override State<_LeaveRequestSheet> createState() => _LeaveRequestSheetState();
}
class _LeaveRequestSheetState extends State<_LeaveRequestSheet> {
  final _api = ApiService();
  final _reasonCtrl = TextEditingController();
  DateTime? _from, _to;
  bool _submitting = false;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  String _fmt(DateTime? d) => d == null ? 'Select date'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final initial = isFrom ? (_from ?? now) : (_to ?? _from ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_from == null || _to == null) {
      showAppToast(context, 'Please select both dates', isError: true);
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      showAppToast(context, 'Please enter a reason', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.requestLeave(fromDate: _fmt(_from), toDate: _fmt(_to), reason: _reasonCtrl.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, 'Could not submit request', isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 18),
            Text('Request Leave', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Text('Your supervisor will review this request.',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _DateField(label: 'FROM', value: _fmt(_from), selected: _from != null, onTap: () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _DateField(label: 'TO', value: _fmt(_to), selected: _to != null, onTap: () => _pickDate(false))),
            ]),
            const SizedBox(height: 14),
            Text('REASON', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
              decoration: const InputDecoration(hintText: 'e.g. Family function, medical...'),
            ),
            const SizedBox(height: 18),
            GkmButton(label: 'Submit Request', icon: Icons.send_rounded, loading: _submitting, onTap: _submit),
          ]),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.value, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.forest : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.calendar_today_rounded, size: 13, color: selected ? AppColors.forest : AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(child: Text(value,
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
                    color: selected ? AppColors.text : AppColors.textFaint),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      ),
    );
  }
}
