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
  Timer? _locTimer, _refreshTimer;
  final _otpCtrls = List.generate(4, (_) => TextEditingController());
  final _otpFocus  = List.generate(4, (_) => FocusNode());
  XFile? _beforeImg, _afterImg;
  final _notesCtrl = TextEditingController();
  int _extraPlants = 0;

  String get _status => _job?['status'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _refreshTimer?.cancel();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await _api.getJobDetail(widget.jobId);
      if (mounted) setState(() { _job = res is Map<String,dynamic> ? res : {}; _loading = false; });
      _manageLocation();
    } catch (_) {
      if (mounted && !quiet) setState(() => _loading = false);
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

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _acting = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.updateBookingStatus(bookingId: widget.jobId, status: newStatus);
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

  Future<void> _verifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length < 4) return;
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
    setState(() => _acting = true);
    try {
      await _api.updateBookingStatus(
        bookingId: widget.jobId, status: 'completed',
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        extraPlants: _extraPlants > 0 ? _extraPlants : null,
        beforeImage: _beforeImg, afterImage: _afterImg,
      );
      await _load(quiet: true);
      if (mounted) showAppToast(context, 'Job completed! Excellent work', isSuccess: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _pickImage(bool isBefore) async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null) setState(() => isBefore ? _beforeImg = f : _afterImg = f);
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

            // ── OTP SECTION (only once gardener has physically arrived) ──
            if (_status == 'arrived') ...[
              _buildOtpSection(),
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

  Widget _buildCompleteForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: cardShadow()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.camera_alt_rounded, size: 18, color: AppColors.success)),
          const SizedBox(width: 12),
          Text('Complete Visit', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
        ]),
        const SizedBox(height: 20),
        // Photos
        Row(children: [
          Expanded(child: _PhotoTile(label: 'Before', file: _beforeImg, onTap: () => _pickImage(true))),
          const SizedBox(width: 12),
          Expanded(child: _PhotoTile(label: 'After', file: _afterImg, onTap: () => _pickImage(false))),
        ]),
        const SizedBox(height: 16),
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
    ).animate().fadeIn(delay: 100.ms);
  }
}

class _PhotoTile extends StatelessWidget {
  final String label;
  final XFile? file;
  final VoidCallback onTap;
  const _PhotoTile({required this.label, required this.file, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: file != null ? AppColors.forest : AppColors.border, width: file != null ? 1.5 : 1, style: BorderStyle.solid),
          image: file != null 
            ? DecorationImage(
                image: kIsWeb ? NetworkImage(file!.path) : FileImage(File(file!.path)) as ImageProvider, 
                fit: BoxFit.cover
              ) 
            : null,
        ),
        child: file == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_a_photo_rounded, size: 24, color: AppColors.textFaint),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ]) : Align(alignment: Alignment.topRight, child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(99)),
            child: Text(label, style: GoogleFonts.poppins(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        )),
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
