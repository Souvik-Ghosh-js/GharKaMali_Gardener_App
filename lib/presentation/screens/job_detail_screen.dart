import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'leads_screen.dart' show kLeadTypeLabels;

/// Human-readable labels for plant-health conditions accepted by the backend.
const Map<String, String> kHealthConditionLabels = {
  'healthy': 'Healthy',
  'needs_attention': 'Needs Attention',
  'pest_attack': 'Pest Attack',
  'overwatering': 'Overwatering',
  'underwatering': 'Underwatering',
  'yellow_leaves': 'Yellow Leaves',
  'root_problem': 'Root Problem',
  'fungus': 'Fungus',
  'plant_dying': 'Plant Dying',
  'repotting_required': 'Repotting Required',
};

/// Human-readable labels for escalation types accepted by the backend.
const Map<String, String> kEscalationTypeLabels = {
  'customer_unavailable': 'Customer Unavailable',
  'access_problem': 'Access Problem',
  'plant_emergency': 'Plant Emergency',
  'accident_damage': 'Accident / Damage',
  'material_required': 'Material Required',
  'customer_complaint': 'Customer Complaint',
  'need_assistance': 'Need Assistance',
};

class JobDetailScreen extends StatefulWidget {
  final int jobId;
  const JobDetailScreen({super.key, required this.jobId});
  @override State<JobDetailScreen> createState() => _JobDetailScreenState();
}
class _JobDetailScreenState extends State<JobDetailScreen> {
  final _api = ApiService();
  final _picker = ImagePicker();
  Map<String, dynamic>? _job;
  bool _loading = true, _acting = false;
  Timer? _locTimer, _refreshTimer, _tickTimer;
  // Wall-clock tick to drive the visit countdown. Rebuilds every second only
  // when a visit is in_progress; cancelled otherwise.
  DateTime _now = DateTime.now();
  final _otpCtrls = List.generate(4, (_) => TextEditingController());
  final _otpFocus  = List.generate(4, (_) => FocusNode());
  final _notesCtrl = TextEditingController();
  int _extraPlants = 0;

  // ── Visit report state ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _checklistItems = [];
  bool _checklistLoading = false, _checklistLoaded = false;
  final Set<String> _checklistDone = {};

  /// Uploaded visit photos grouped by type ('before' | 'after' | 'problem').
  Map<String, List<Map<String, dynamic>>> _photos = {};
  /// Photos taken but not (yet) uploaded — uploading or failed (tap to retry).
  final List<_PendingPhoto> _pending = [];
  bool _reportLoading = false;
  Map<String, dynamic>? _report;

  // Supervisor is the same for every job — fetch once per app session.
  static Map<String, dynamic>? _supervisorCache;
  static bool _supervisorFetched = false;
  Map<String, dynamic>? _supervisor;

  // Fallback when GET /gardener/checklist is unreachable.
  static const _fallbackChecklist = [
    {'key': 'watering', 'label': 'Watering done', 'required': false},
    {'key': 'weeding', 'label': 'Weeding done', 'required': false},
    {'key': 'pruning', 'label': 'Pruning / trimming done', 'required': false},
    {'key': 'fertilizer', 'label': 'Fertilizer applied', 'required': false},
    {'key': 'pest_check', 'label': 'Pest check done', 'required': false},
    {'key': 'cleanup', 'label': 'Garden cleaned up', 'required': false},
  ];

  String get _status => _job?['status'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadSupervisor();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Visit countdown — starts ticking when status is `in_progress` (OTP verified).
  // Reads zone-configured `ondemand_visit_minutes` from the booking's geofence,
  // adds any customer-purchased `extra_time_minutes`. Falls back to 60 min.
  // ───────────────────────────────────────────────────────────────────────────
  void _manageTickTimer() {
    if (_status == 'in_progress' && _tickTimer == null) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
      });
    } else if (_status != 'in_progress' && _tickTimer != null) {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  DateTime? get _visitStartedAt {
    final raw = _job?['started_at'] ?? _job?['otp_verified_at'];
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  int get _visitAllowedMinutes {
    final gf = _job?['geofenceRef'];
    int base = 60;
    if (gf is Map && gf['visit_minutes'] != null) {
      base = int.tryParse(gf['visit_minutes'].toString()) ?? 60;
    }
    final extra = int.tryParse((_job?['extra_time_minutes'] ?? 0).toString()) ?? 0;
    return base + extra;
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await _api.getJobDetail(widget.jobId);
      if (mounted) setState(() { _job = res is Map<String,dynamic> ? res : {}; _loading = false; });
      _manageLocation();
      _manageTickTimer();
      // Once the visit becomes actionable, pull the checklist + report.
      if (['arrived', 'in_progress'].contains(_status)) {
        if (!_checklistLoaded && !_checklistLoading) _loadChecklist();
        if (_report == null && !_reportLoading) _loadReport();
      }
    } catch (_) {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _loadSupervisor() async {
    if (_supervisorFetched) {
      _supervisor = _supervisorCache;
      return;
    }
    try {
      final res = await _api.getSupervisor();
      _supervisorCache = res;
      _supervisorFetched = true;
      if (mounted) setState(() => _supervisor = res);
    } catch (_) {/* row simply stays hidden */}
  }

  Future<void> _loadChecklist() async {
    _checklistLoading = true;
    try {
      final type = _job?['booking_type']?.toString() == 'subscription' ? 'subscription' : 'ondemand';
      final items = await _api.getChecklist(type);
      if (mounted) setState(() {
        _checklistItems = items.isNotEmpty ? items : List<Map<String, dynamic>>.from(_fallbackChecklist);
        _checklistLoaded = true;
      });
    } catch (_) {
      if (mounted && _checklistItems.isEmpty) {
        setState(() => _checklistItems = List<Map<String, dynamic>>.from(_fallbackChecklist));
      }
    } finally {
      _checklistLoading = false;
    }
  }

  Future<void> _loadReport() async {
    _reportLoading = true;
    try {
      final res = await _api.getVisitReport(widget.jobId);
      if (mounted) setState(() {
        _report = res;
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final p in (res['photos'] as List? ?? [])) {
          if (p is! Map) continue;
          final t = p['type']?.toString() ?? 'before';
          (grouped[t] ??= []).add(Map<String, dynamic>.from(p));
        }
        _photos = grouped;
      });
    } catch (_) {/* keep whatever we had */} finally {
      _reportLoading = false;
    }
  }

  Future<void> _manageLocation() async {
    final active = ['en_route','arrived','in_progress'].contains(_status);
    if (active && _locTimer == null) {
      // Permission check
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) showAppToast(context, 'Location permission is required for tracking', isError: true);
        return;
      }

      _locTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          await _api.updateLocation(pos.latitude, pos.longitude, bookingId: widget.jobId);
        } catch (_) {}
      });
    } else if (!active) {
      _locTimer?.cancel(); _locTimer = null;
    }
  }

  /// Best-effort current GPS fix; null when permission is denied or it times out.
  Future<Position?> _currentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      return await Geolocator
          .getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _acting = true);
    HapticFeedback.mediumImpact();
    // Send current GPS with 'arrived' (and 'completed' — see _completeJob).
    Position? pos;
    if (newStatus == 'arrived') pos = await _currentPosition();
    try {
      await _api.updateBookingStatus(
        bookingId: widget.jobId, status: newStatus,
        latitude: pos?.latitude, longitude: pos?.longitude,
      );
      await _load(quiet: true);
      if (mounted) showAppToast(context,
        newStatus == 'en_route' ? 'Journey started! Location tracking active' :
        newStatus == 'arrived'  ? 'Arrived! Ask the customer for the OTP to start service.' :
        newStatus == 'completed'? 'Job completed! Great work' : 'Status updated',
        isSuccess: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _markFailed() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _FailedReasonDialog(),
    );
    if (reason == null || !mounted) return;
    setState(() => _acting = true);
    HapticFeedback.heavyImpact();
    try {
      await _api.updateBookingStatus(bookingId: widget.jobId, status: 'failed', notes: reason);
      await _load(quiet: true);
      if (mounted) showAppToast(context, 'Visit marked as failed', isError: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _callCustomer() {
    final phone = _job?['customer']?['phone']?.toString();
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
  }

  void _callSupervisor() {
    final phone = _supervisor?['phone']?.toString();
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length < 4) return;
    if ((_photos['before']?.length ?? 0) < 1) {
      showAppToast(context, 'Take at least one Before photo before starting work', isError: true);
      return;
    }
    setState(() => _acting = true);
    try {
      await _api.verifyVisitOtp(widget.jobId, otp);
      await _load(quiet: true);
      if (mounted) showAppToast(context, 'OTP verified! Visit started', isSuccess: true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _acting = false);
        for (final c in _otpCtrls) c.clear();
        _otpFocus[0].requestFocus();
        showAppToast(context, e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _completeJob() async {
    if ((_photos['before']?.length ?? 0) < 1) {
      showAppToast(context, 'Take at least one Before photo first', isError: true);
      return;
    }
    if ((_photos['after']?.length ?? 0) < 1) {
      showAppToast(context, 'Take at least one After photo before completing', isError: true);
      return;
    }
    setState(() => _acting = true);
    final pos = await _currentPosition();
    try {
      await _api.updateBookingStatus(
        bookingId: widget.jobId, status: 'completed',
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        extraPlants: _extraPlants > 0 ? _extraPlants : null,
        checklistDone: _checklistDone.toList(),
        latitude: pos?.latitude, longitude: pos?.longitude,
      );
      await _load(quiet: true);
      if (mounted) showAppToast(context, 'Job completed! Excellent work', isSuccess: true);
    } on ApiException catch (e) {
      // Server may 400 with "After photo is required…" — surface its message.
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  // ── VISIT PHOTOS ──────────────────────────────────────────────────────────
  int _photoCount(String type) =>
      (_photos[type]?.length ?? 0) + _pending.where((p) => p.type == type).length;

  Future<void> _addVisitPhoto(String type) async {
    if (_photoCount(type) >= 10) {
      showAppToast(context, 'Maximum 10 $type photos allowed', isError: true);
      return;
    }
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f == null || !mounted) return;
    final p = _PendingPhoto(f, type);
    setState(() => _pending.add(p));
    await _uploadPendingPhoto(p);
  }

  Future<void> _uploadPendingPhoto(_PendingPhoto p) async {
    if (mounted) setState(() { p.uploading = true; p.failed = false; });
    final pos = await _currentPosition();
    try {
      final created = await _api.uploadVisitPhoto(
        bookingId: widget.jobId, photo: p.file, type: p.type,
        latitude: pos?.latitude, longitude: pos?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _pending.remove(p);
        (_photos[p.type] ??= []).add(created);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { p.uploading = false; p.failed = true; });
      showAppToast(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() { p.uploading = false; p.failed = true; });
      showAppToast(context, 'Photo upload failed — tap the photo to retry', isError: true);
    }
  }

  Future<void> _openMaps() async {
    final lat = _job?['service_latitude'];
    final lng = _job?['service_longitude'];
    final addr = _job?['service_address'];
    final uri = lat != null && lng != null
        ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng')
        : Uri.parse('https://www.google.com/maps/search/${Uri.encodeComponent(addr ?? '')}');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── BOTTOM SHEETS ─────────────────────────────────────────────────────────
  Future<T?> _openSheet<T>(Widget sheet) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => sheet,
      );

  Future<void> _openChecklistSheet() async {
    if (!_checklistLoaded && !_checklistLoading) await _loadChecklist();
    if (!mounted) return;
    await _openSheet(_ChecklistSheet(
      items: _checklistItems.isNotEmpty ? _checklistItems : List<Map<String, dynamic>>.from(_fallbackChecklist),
      done: _checklistDone,
    ));
    if (mounted) setState(() {}); // reflect selections on the report row
  }

  Future<void> _openHealthSheet() async {
    final submitted = await _openSheet<bool>(_HealthSheet(bookingId: widget.jobId));
    if (submitted == true && mounted) {
      showAppToast(context, 'Plant health report saved', isSuccess: true);
      _loadReport();
    }
  }

  Future<void> _openMaterialsSheet() async {
    final submitted = await _openSheet<bool>(_MaterialsSheet(bookingId: widget.jobId));
    if (submitted == true && mounted) {
      showAppToast(context, 'Materials recorded', isSuccess: true);
      _loadReport();
    }
  }

  Future<void> _openLeadSheet() async {
    final submitted = await _openSheet<bool>(_LeadSheet(bookingId: widget.jobId));
    if (submitted == true && mounted) {
      showAppToast(context, 'Sent to supervisor for approval', isSuccess: true);
    }
  }

  Future<void> _openEscalationSheet() async {
    final submitted = await _openSheet<bool>(_EscalationSheet(bookingId: widget.jobId));
    if (submitted == true && mounted) {
      showAppToast(context, 'Issue reported to your supervisor', isSuccess: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.forest)));
    if (_job == null) return Scaffold(appBar: AppBar(backgroundColor: AppColors.forest), body: const EmptyState(title: 'Job not found', subtitle: 'This job may have been cancelled'));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        // ── HEADER ────────────────────────────────────────────────────────
        SliverToBoxAdapter(child: GradientHeader(
          bottomPadding: 52,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Row(children: [
                const Icon(Icons.arrow_back_ios_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Text('Jobs', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_job!['booking_number']?.toString() ?? '#${_job!['id']}',
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Row(children: [
                  StatusBadge(_status),
                  if (['en_route','arrived','in_progress'].contains(_status)) ...[
                    const SizedBox(width: 10),
                    const LiveIndicator(),
                  ],
                ]),
              ])),
              GestureDetector(
                onTap: _openMaps,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white24)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.navigation_rounded, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('Navigate', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ]),
        )),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(delegate: SliverChildListDelegate([
            // ── JOB INFO CARD ────────────────────────────────────────────
            PremiumCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('JOB DETAILS', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1)),
              const SizedBox(height: 14),
              InfoRow(icon: Icons.location_on_rounded, label: 'ADDRESS', value: _job!['service_address'] ?? '—'),
              // Customer row with call button
              Row(children: [
                Expanded(child: InfoRow(icon: Icons.person_rounded, label: 'CUSTOMER', value: _job!['customer']?['name'] ?? '—')),
                if (_job!['customer']?['phone'] != null)
                  GestureDetector(
                    onTap: _callCustomer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.success.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.call_rounded, size: 13, color: AppColors.success),
                        const SizedBox(width: 5),
                        Text('Call', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
                      ]),
                    ),
                  ),
              ]),
              InfoRow(icon: Icons.access_time_rounded, label: 'TIME', value: _job!['scheduled_time'] ?? 'Flexible'),
              InfoRow(icon: Icons.local_florist_rounded, label: 'PLANTS', value: '${_job!['plant_count'] ?? '?'} plants'),
              if (_job!['customer_notes'] != null && _job!['customer_notes'].toString().isNotEmpty)
                InfoRow(icon: Icons.sticky_note_2_outlined, label: 'NOTES', value: _job!['customer_notes'].toString()),
            ])).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 12),

            // ── ADD-ONS ──────────────────────────────────────────────────
            if ((_job!['addons'] as List? ?? []).isNotEmpty) ...[
              PremiumCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ADD-ONS', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 12),
                ...(_job!['addons'] as List).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Text(a['addon']?['name'] ?? a['name'] ?? '—', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2)),
                  ]),
                )),
              ])).animate().fadeIn(delay: 50.ms),
              const SizedBox(height: 12),
            ],

            // ── PHOTOS (arrived: before only · in_progress: all types) ───
            if (['arrived', 'in_progress'].contains(_status)) ...[
              _buildPhotosCard(),
              const SizedBox(height: 12),
            ],

            // ── OTP SECTION (only once gardener has physically arrived) ──
            if (_status == 'arrived') ...[
              _buildOtpSection(),
              const SizedBox(height: 12),
            ],

            // ── VISIT COUNTDOWN TIMER ────────────────────────────────────
            if (_status == 'in_progress') ...[
              _buildVisitTimer(),
              const SizedBox(height: 12),
            ],

            // ── VISIT REPORT ─────────────────────────────────────────────
            if (_status == 'in_progress') ...[
              _buildVisitReport(),
              const SizedBox(height: 12),
            ],

            // ── COMPLETE JOB FORM ────────────────────────────────────────
            if (_status == 'in_progress') ...[
              _buildCompleteForm(),
              const SizedBox(height: 12),
            ],

            // ── ACTION BUTTONS ───────────────────────────────────────────
            if (_status == 'assigned') ...[
              GkmButton(label: 'Start Journey', icon: Icons.directions_run_rounded, loading: _acting, onTap: () => _updateStatus('en_route'), color: AppColors.info),
              const SizedBox(height: 12),
            ],
            if (_status == 'en_route') ...[
              GkmButton(label: 'Mark Arrived', icon: Icons.location_on_rounded, loading: _acting, onTap: () => _updateStatus('arrived'), color: AppColors.warning),
              const SizedBox(height: 12),
            ],
            // Mark Failed — customer not home (only available after arriving)
            if (_status == 'arrived') ...[
              const SizedBox(height: 4),
              GkmButton(
                label: 'Customer Not Home',
                icon: Icons.person_off_rounded,
                loading: _acting,
                onTap: _markFailed,
                outline: true,
                danger: true,
              ),
              const SizedBox(height: 12),
            ],

            // ── RATING RECEIVED ──────────────────────────────────────────
            if (_job!['rating'] != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.gold.withOpacity(0.15), AppColors.gold.withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.star_rounded, color: AppColors.gold, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_job!['rating']}/5 stars received', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                    if (_job!['review'] != null && _job!['review'].toString().isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text('"${_job!['review']}"', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic))),
                  ])),
                ]),
              ).animate().fadeIn(delay: 200.ms),
            ],
          ])),
        ),
      ]),
    );
  }

  Widget _buildVisitTimer() {
    final startedAt = _visitStartedAt;
    final allowedMinutes = _visitAllowedMinutes;
    final elapsed = startedAt == null ? Duration.zero : _now.difference(startedAt);
    final total = Duration(minutes: allowedMinutes);
    final remaining = total - elapsed;
    final overtime = remaining.isNegative;
    final progress = startedAt == null
        ? 0.0
        : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    Duration display = overtime ? -remaining : (remaining.isNegative ? Duration.zero : remaining);
    final mm = display.inMinutes.toString().padLeft(2, '0');
    final ss = (display.inSeconds % 60).toString().padLeft(2, '0');

    final accent = overtime
        ? AppColors.error
        : (remaining.inMinutes < 10 ? AppColors.warning : AppColors.success);

    final extraMinutes = int.tryParse((_job?['extra_time_minutes'] ?? 0).toString()) ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent.withOpacity(0.10), accent.withOpacity(0.02)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(overtime ? Icons.alarm_rounded : Icons.timer_rounded, color: accent, size: 18),
          const SizedBox(width: 8),
          Text(overtime ? 'OVERTIME' : 'VISIT TIMER',
              style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: accent, letterSpacing: 1)),
          const Spacer(),
          Text('Allowed: ${allowedMinutes} min',
              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(overtime ? '+$mm:$ss' : '$mm:$ss',
              style: GoogleFonts.poppins(fontSize: 42, fontWeight: FontWeight.w900, color: accent, height: 1, letterSpacing: -1)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(overtime ? 'over' : 'remaining',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text2)),
          ),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: accent.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        if (extraMinutes > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.add_circle_outline_rounded, size: 13, color: AppColors.forest),
            const SizedBox(width: 6),
            Text('Customer added $extraMinutes min',
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.forest)),
          ]),
        ],
        if (startedAt != null) ...[
          const SizedBox(height: 6),
          Text('Started at ${TimeOfDay.fromDateTime(startedAt).format(context)}',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
        ],
      ]),
    );
  }

  Widget _buildOtpSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.5),
        boxShadow: cardShadow(),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.forest.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.lock_rounded, size: 18, color: AppColors.forest)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Verify Customer OTP', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text('Ask customer for 4-digit OTP', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
          ])),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) => Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
          child: SizedBox(width: 58, child: TextFormField(
            controller: _otpCtrls[i],
            focusNode: _otpFocus[i],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text),
            decoration: InputDecoration(
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border:          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.forest, width: 2)),
              filled: true,
              fillColor: _otpCtrls[i].text.isNotEmpty ? AppColors.forest.withOpacity(0.04) : AppColors.bgSubtle,
            ),
            onChanged: (v) {
              if (v.isNotEmpty && i < 3) _otpFocus[i+1].requestFocus();
              if (_otpCtrls.every((c) => c.text.isNotEmpty)) _verifyOtp();
            },
          )),
        ))),
        const SizedBox(height: 20),
        GkmButton(label: 'Verify & Start Visit', loading: _acting, onTap: _verifyOtp),
      ]),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0);
  }

  // ── PHOTOS CARD ───────────────────────────────────────────────────────────
  Widget _buildPhotosCard() {
    final arrivedOnly = _status == 'arrived';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: cardShadow()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.camera_alt_rounded, size: 18, color: AppColors.info)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Visit Photos', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(arrivedOnly
                ? 'Take at least 1 Before photo to start work'
                : '1 Before photo to start · 1 After photo to complete',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
          ])),
        ]),
        const SizedBox(height: 16),
        _PhotoTypeSection(
          label: 'BEFORE',
          uploaded: _photos['before'] ?? const [],
          pending: _pending.where((p) => p.type == 'before').toList(),
          onAdd: () => _addVisitPhoto('before'),
          onRetry: _uploadPendingPhoto,
        ),
        if (!arrivedOnly) ...[
          const SizedBox(height: 14),
          _PhotoTypeSection(
            label: 'AFTER',
            uploaded: _photos['after'] ?? const [],
            pending: _pending.where((p) => p.type == 'after').toList(),
            onAdd: () => _addVisitPhoto('after'),
            onRetry: _uploadPendingPhoto,
          ),
          const SizedBox(height: 14),
          _PhotoTypeSection(
            label: 'PROBLEM (OPTIONAL)',
            uploaded: _photos['problem'] ?? const [],
            pending: _pending.where((p) => p.type == 'problem').toList(),
            onAdd: () => _addVisitPhoto('problem'),
            onRetry: _uploadPendingPhoto,
          ),
        ],
      ]),
    ).animate().fadeIn(delay: 100.ms);
  }

  // ── VISIT REPORT CARD ─────────────────────────────────────────────────────
  Widget _buildVisitReport() {
    final healthCount = (_report?['health_reports'] as List?)?.length ?? 0;
    final materialsCount = (_report?['materials'] as List?)?.length ?? 0;
    final checklistTotal = _checklistItems.isNotEmpty ? _checklistItems.length : _fallbackChecklist.length;
    final supPhone = _supervisor?['phone']?.toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: cardShadow()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.forest.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.assignment_rounded, size: 18, color: AppColors.forest)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Visit Report', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text('Record what you did during this visit', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
          ])),
        ]),
        const SizedBox(height: 14),
        _ReportRow(
          icon: Icons.checklist_rounded, color: AppColors.success,
          title: 'Checklist',
          subtitle: '${_checklistDone.length} of $checklistTotal tasks done',
          done: _checklistDone.isNotEmpty,
          onTap: _openChecklistSheet,
        ),
        _ReportRow(
          icon: Icons.local_florist_rounded, color: AppColors.forest,
          title: 'Plant Health',
          subtitle: healthCount > 0 ? '$healthCount report${healthCount == 1 ? '' : 's'} submitted' : 'Log plant conditions',
          done: healthCount > 0,
          onTap: _openHealthSheet,
        ),
        _ReportRow(
          icon: Icons.inventory_2_rounded, color: AppColors.info,
          title: 'Materials Used',
          subtitle: materialsCount > 0 ? '$materialsCount item${materialsCount == 1 ? '' : 's'} recorded' : 'Vermicompost, fertiliser, pots...',
          done: materialsCount > 0,
          onTap: _openMaterialsSheet,
        ),
        _ReportRow(
          icon: Icons.lightbulb_outline_rounded, color: AppColors.goldDark,
          title: 'Suggest Service',
          subtitle: 'Recommend a service to this customer',
          onTap: _openLeadSheet,
        ),
        _ReportRow(
          icon: Icons.report_problem_rounded, color: AppColors.error,
          title: 'Report Issue',
          subtitle: 'Escalate a problem to your supervisor',
          onTap: _openEscalationSheet,
        ),
        if (supPhone != null && supPhone.isNotEmpty)
          _ReportRow(
            icon: Icons.support_agent_rounded, color: AppColors.warning,
            title: 'Call Supervisor',
            subtitle: _supervisor?['name']?.toString() ?? 'Get help on this visit',
            onTap: _callSupervisor,
            isLast: true,
          ),
      ]),
    ).animate().fadeIn(delay: 120.ms);
  }

  Widget _buildCompleteForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: cardShadow()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success)),
          const SizedBox(width: 12),
          Text('Complete Visit', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
        ]),
        const SizedBox(height: 20),
        // Extra plants
        Text('EXTRA PLANTS SERVICED', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.bgSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _CountBtn(icon: Icons.remove, onTap: _extraPlants > 0 ? () => setState(() => _extraPlants--) : null),
            SizedBox(width: 48, child: Text('$_extraPlants', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text))),
            _CountBtn(icon: Icons.add, onTap: () => setState(() => _extraPlants++)),
          ]),
        ),
        const SizedBox(height: 16),
        Text('NOTES (OPTIONAL)', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
          decoration: const InputDecoration(hintText: 'Any observations about the garden...'),
        ),
        const SizedBox(height: 20),
        GkmButton(label: 'Mark Job Complete', icon: Icons.check_circle_rounded, loading: _acting, onTap: _completeJob),
      ]),
    ).animate().fadeIn(delay: 140.ms);
  }
}

// ── PENDING PHOTO ────────────────────────────────────────────────────────────
class _PendingPhoto {
  final XFile file;
  final String type;
  bool uploading = true;
  bool failed = false;
  _PendingPhoto(this.file, this.type);
}

// ── PHOTO TYPE SECTION (grid of thumbs + add button) ─────────────────────────
class _PhotoTypeSection extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> uploaded;
  final List<_PendingPhoto> pending;
  final VoidCallback onAdd;
  final void Function(_PendingPhoto) onRetry;
  const _PhotoTypeSection({
    required this.label, required this.uploaded, required this.pending,
    required this.onAdd, required this.onRetry,
  });

  String? _url(Map<String, dynamic> p) =>
      (p['url'] ?? p['photo_url'] ?? p['image_url'])?.toString();

  @override
  Widget build(BuildContext context) {
    final count = uploaded.length + pending.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(width: 6),
        if (count > 0)
          Text('$count/10', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textFaint)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ...uploaded.map((p) {
          final url = _url(p);
          return _thumbFrame(
            border: AppColors.forest,
            child: url != null
                ? Image.network(url, fit: BoxFit.cover, width: 72, height: 72,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 20, color: AppColors.textFaint))
                : const Icon(Icons.photo_rounded, size: 20, color: AppColors.textFaint),
          );
        }),
        ...pending.map((p) => GestureDetector(
          onTap: p.failed ? () => onRetry(p) : null,
          child: _thumbFrame(
            border: p.failed ? AppColors.error : AppColors.border,
            child: Stack(fit: StackFit.expand, children: [
              kIsWeb
                  ? Image.network(p.file.path, fit: BoxFit.cover)
                  : Image.file(File(p.file.path), fit: BoxFit.cover),
              Container(color: Colors.black38),
              Center(
                child: p.failed
                    ? const Icon(Icons.refresh_rounded, size: 22, color: Colors.white)
                    : const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ),
            ]),
          ),
        )),
        if (count < 10)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.bgSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.add_a_photo_rounded, size: 20, color: AppColors.textFaint),
            ),
          ),
      ]),
    ]);
  }

  Widget _thumbFrame({required Color border, required Widget child}) => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

// ── REPORT ACTION ROW ────────────────────────────────────────────────────────
class _ReportRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final bool done;
  final bool isLast;
  final VoidCallback onTap;
  const _ReportRow({
    required this.icon, required this.color, required this.title,
    required this.subtitle, required this.onTap, this.done = false, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? color.withOpacity(0.4) : AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (done)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
            ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textFaint),
        ]),
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CountBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: onTap != null ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: onTap != null ? AppColors.border : Colors.transparent),
        ),
        child: Icon(icon, size: 18, color: onTap != null ? AppColors.forest : AppColors.textFaint),
      ),
    );
  }
}

// ── SHEET SCAFFOLD (shared chrome for the bottom sheets) ─────────────────────
class _SheetScaffold extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  const _SheetScaffold({required this.title, required this.subtitle, required this.children});
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
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              Text(title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 4),
              Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 18),
              ...children,
            ]),
          ),
        ),
      ),
    );
  }
}

// ── CHECKLIST SHEET ──────────────────────────────────────────────────────────
class _ChecklistSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Set<String> done; // shared with the screen — labels of completed tasks
  const _ChecklistSheet({required this.items, required this.done});
  @override State<_ChecklistSheet> createState() => _ChecklistSheetState();
}
class _ChecklistSheetState extends State<_ChecklistSheet> {
  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Task Checklist',
      subtitle: 'Tick off tasks as you complete them.',
      children: [
        ...widget.items.map((item) {
          final label = (item['label'] ?? item['key'] ?? '').toString();
          final required = item['required'] == true;
          final checked = widget.done.contains(label);
          return GestureDetector(
            onTap: () => setState(() {
              if (checked) { widget.done.remove(label); } else { widget.done.add(label); }
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: checked ? AppColors.success.withOpacity(0.07) : AppColors.bgSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: checked ? AppColors.success.withOpacity(0.4) : AppColors.border),
              ),
              child: Row(children: [
                Icon(
                  checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: checked ? AppColors.success : AppColors.textFaint,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  color: checked ? AppColors.success : AppColors.text2,
                ))),
                if (required)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.18), borderRadius: BorderRadius.circular(99)),
                    child: Text('REQUIRED', style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.goldDark, letterSpacing: 0.5)),
                  ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 12),
        GkmButton(label: 'Done', icon: Icons.check_rounded, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

// ── PLANT HEALTH SHEET ───────────────────────────────────────────────────────
class _HealthSheet extends StatefulWidget {
  final int bookingId;
  const _HealthSheet({required this.bookingId});
  @override State<_HealthSheet> createState() => _HealthSheetState();
}
class _HealthSheetState extends State<_HealthSheet> {
  final _api = ApiService();
  final _picker = ImagePicker();
  final _remarksCtrl = TextEditingController();
  final Set<String> _conditions = {};
  XFile? _photo;
  bool _submitting = false;

  @override
  void dispose() { _remarksCtrl.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) setState(() => _photo = f);
  }

  Future<void> _submit() async {
    if (_conditions.isEmpty) {
      showAppToast(context, 'Select at least one condition', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      String? photoUrl;
      if (_photo != null) {
        final created = await _api.uploadVisitPhoto(
            bookingId: widget.bookingId, photo: _photo!, type: 'health');
        photoUrl = (created['url'] ?? created['photo_url'] ?? created['image_url'])?.toString();
      }
      await _api.submitHealthReport(
        widget.bookingId,
        conditions: _conditions.toList(),
        remarks: _remarksCtrl.text.trim(),
        photoUrl: photoUrl,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, 'Could not save health report', isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Plant Health',
      subtitle: 'Select all conditions that apply to this garden.',
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: kHealthConditionLabels.entries.map((e) {
            final selected = _conditions.contains(e.key);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) { _conditions.remove(e.key); } else { _conditions.add(e.key); }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.forest : AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: selected ? AppColors.forest : AppColors.border),
                ),
                child: Text(e.value, style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.text2,
                )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('REMARKS (OPTIONAL)', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _remarksCtrl,
          maxLines: 3,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
          decoration: const InputDecoration(hintText: 'e.g. Aphids on the rose bushes...'),
        ),
        const SizedBox(height: 16),
        Text('PHOTO (OPTIONAL)', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            height: 90, width: 90,
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _photo != null ? AppColors.forest : AppColors.border, width: _photo != null ? 1.5 : 1),
              image: _photo != null
                  ? DecorationImage(
                      image: kIsWeb ? NetworkImage(_photo!.path) : FileImage(File(_photo!.path)) as ImageProvider,
                      fit: BoxFit.cover)
                  : null,
            ),
            child: _photo == null
                ? const Icon(Icons.add_a_photo_rounded, size: 22, color: AppColors.textFaint)
                : null,
          ),
        ),
        const SizedBox(height: 18),
        GkmButton(label: 'Save Health Report', icon: Icons.local_florist_rounded, loading: _submitting, onTap: _submit),
      ],
    );
  }
}

// ── MATERIALS SHEET ──────────────────────────────────────────────────────────
class _MaterialsSheet extends StatefulWidget {
  final int bookingId;
  const _MaterialsSheet({required this.bookingId});
  @override State<_MaterialsSheet> createState() => _MaterialsSheetState();
}
class _MaterialsSheetState extends State<_MaterialsSheet> {
  final _api = ApiService();
  final List<_MaterialRowCtrl> _rows = [_MaterialRowCtrl()];
  bool _submitting = false;

  static const _quickItems = ['Vermicompost', 'Fertiliser', 'Pesticide', 'Pots', 'Other'];

  @override
  void dispose() {
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  void _quickAdd(String name) {
    // Fill the first empty row, otherwise append a new one.
    final target = _rows.where((r) => r.item.text.trim().isEmpty).toList();
    setState(() {
      if (target.isNotEmpty) {
        if (name != 'Other') target.first.item.text = name;
      } else {
        final r = _MaterialRowCtrl();
        if (name != 'Other') r.item.text = name;
        _rows.add(r);
      }
    });
  }

  Future<void> _submit() async {
    final items = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final name = r.item.text.trim();
      if (name.isEmpty) continue;
      final qty = num.tryParse(r.qty.text.trim()) ?? 1;
      final unit = r.unit.text.trim();
      items.add({'item': name, 'quantity': qty, if (unit.isNotEmpty) 'unit': unit});
    }
    if (items.isEmpty) {
      showAppToast(context, 'Add at least one material', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.submitMaterials(widget.bookingId, items);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, 'Could not save materials', isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Materials Used',
      subtitle: 'What did you use or install during this visit?',
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _quickItems.map((q) => GestureDetector(
            onTap: () => _quickAdd(q),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.forest.withOpacity(0.06),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.forest.withOpacity(0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, size: 13, color: AppColors.forest),
                const SizedBox(width: 4),
                Text(q, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.forest)),
              ]),
            ),
          )).toList(),
        ),
        const SizedBox(height: 14),
        ...List.generate(_rows.length, (i) {
          final r = _rows[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(flex: 5, child: TextField(
                controller: r.item,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.text2),
                decoration: const InputDecoration(hintText: 'Item', isDense: true),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(
                controller: r.qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.text2),
                decoration: const InputDecoration(hintText: 'Qty', isDense: true),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: TextField(
                controller: r.unit,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.text2),
                decoration: const InputDecoration(hintText: 'Unit (kg)', isDense: true),
              )),
              if (_rows.length > 1)
                GestureDetector(
                  onTap: () {
                    final removed = _rows.removeAt(i);
                    setState(() {});
                    // Dispose after the frame so the TextFields detach first.
                    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.error),
                  ),
                ),
            ]),
          );
        }),
        GestureDetector(
          onTap: () => setState(() => _rows.add(_MaterialRowCtrl())),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.forest),
              const SizedBox(width: 6),
              Text('Add another item', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.forest)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        GkmButton(label: 'Save Materials', icon: Icons.inventory_2_rounded, loading: _submitting, onTap: _submit),
      ],
    );
  }
}

class _MaterialRowCtrl {
  final item = TextEditingController();
  final qty = TextEditingController();
  final unit = TextEditingController();
  void dispose() { item.dispose(); qty.dispose(); unit.dispose(); }
}

// ── SUGGEST SERVICE (LEAD) SHEET ─────────────────────────────────────────────
class _LeadSheet extends StatefulWidget {
  final int bookingId;
  const _LeadSheet({required this.bookingId});
  @override State<_LeadSheet> createState() => _LeadSheetState();
}
class _LeadSheetState extends State<_LeadSheet> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  String? _type;
  bool _submitting = false;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_type == null) {
      showAppToast(context, 'Select a service type', isError: true);
      return;
    }
    if (_noteCtrl.text.trim().isEmpty) {
      showAppToast(context, 'Add a short note for your supervisor', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.createLead(bookingId: widget.bookingId, type: _type!, note: _noteCtrl.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, 'Could not send suggestion', isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Suggest Service',
      subtitle: 'Recommend an extra service for this customer. Your supervisor will follow up.',
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: kLeadTypeLabels.entries.map((e) {
            final selected = _type == e.key;
            return GestureDetector(
              onTap: () => setState(() => _type = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.forest : AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: selected ? AppColors.forest : AppColors.border),
                ),
                child: Text(e.value, style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.text2,
                )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('NOTE', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
          decoration: const InputDecoration(hintText: 'e.g. Customer wants 4 large pots for the balcony...'),
        ),
        const SizedBox(height: 18),
        GkmButton(label: 'Send Suggestion', icon: Icons.send_rounded, loading: _submitting, onTap: _submit),
      ],
    );
  }
}

// ── REPORT ISSUE (ESCALATION) SHEET ──────────────────────────────────────────
class _EscalationSheet extends StatefulWidget {
  final int bookingId;
  const _EscalationSheet({required this.bookingId});
  @override State<_EscalationSheet> createState() => _EscalationSheetState();
}
class _EscalationSheetState extends State<_EscalationSheet> {
  final _api = ApiService();
  final _picker = ImagePicker();
  final _noteCtrl = TextEditingController();
  String? _type;
  XFile? _photo;
  bool _submitting = false;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) setState(() => _photo = f);
  }

  Future<void> _submit() async {
    if (_type == null) {
      showAppToast(context, 'Select the issue type', isError: true);
      return;
    }
    if (_noteCtrl.text.trim().isEmpty) {
      showAppToast(context, 'Describe the issue briefly', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.createEscalation(
        bookingId: widget.bookingId, type: _type!, note: _noteCtrl.text.trim(), photo: _photo);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, e.message, isError: true); }
    } catch (_) {
      if (mounted) { setState(() => _submitting = false); showAppToast(context, 'Could not report the issue', isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Report Issue',
      subtitle: 'This alerts your supervisor immediately.',
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: kEscalationTypeLabels.entries.map((e) {
            final selected = _type == e.key;
            return GestureDetector(
              onTap: () => setState(() => _type = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.error : AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: selected ? AppColors.error : AppColors.border),
                ),
                child: Text(e.value, style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.text2,
                )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('WHAT HAPPENED?', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
          decoration: const InputDecoration(hintText: 'Describe the problem...'),
        ),
        const SizedBox(height: 16),
        Text('PHOTO (OPTIONAL)', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            height: 90, width: 90,
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _photo != null ? AppColors.error : AppColors.border, width: _photo != null ? 1.5 : 1),
              image: _photo != null
                  ? DecorationImage(
                      image: kIsWeb ? NetworkImage(_photo!.path) : FileImage(File(_photo!.path)) as ImageProvider,
                      fit: BoxFit.cover)
                  : null,
            ),
            child: _photo == null
                ? const Icon(Icons.add_a_photo_rounded, size: 22, color: AppColors.textFaint)
                : null,
          ),
        ),
        const SizedBox(height: 18),
        GkmButton(label: 'Report Issue', icon: Icons.report_problem_rounded, danger: true, loading: _submitting, onTap: _submit),
      ],
    );
  }
}

// ── FAILED REASON DIALOG ──────────────────────────────────────────────────────
class _FailedReasonDialog extends StatefulWidget {
  @override State<_FailedReasonDialog> createState() => _FailedReasonDialogState();
}
class _FailedReasonDialogState extends State<_FailedReasonDialog> {
  final _ctrl = TextEditingController();
  String _selected = 'Customer not home';

  static const _reasons = [
    'Customer not home',
    'Customer not responding',
    'Address not found',
    'Gate locked / no access',
    'Other',
  ];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Mark Visit Failed', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select reason:', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ..._reasons.map((r) => GestureDetector(
            onTap: () => setState(() => _selected = r),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _selected == r ? AppColors.error.withOpacity(0.08) : AppColors.bgSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _selected == r ? AppColors.error.withOpacity(0.4) : AppColors.border),
              ),
              child: Text(r, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500,
                color: _selected == r ? AppColors.error : AppColors.text2)),
            ),
          )),
          if (_selected == 'Other') ...[
            TextField(
              controller: _ctrl,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.text2),
              decoration: const InputDecoration(hintText: 'Describe the issue...'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: () {
            final reason = _selected == 'Other' ? _ctrl.text.trim() : _selected;
            if (reason.isEmpty) return;
            Navigator.pop(context, reason);
          },
          child: Text('Confirm', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.error)),
        ),
      ],
    );
  }
}
