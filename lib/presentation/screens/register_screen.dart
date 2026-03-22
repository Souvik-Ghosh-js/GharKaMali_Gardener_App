import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  final _api = ApiService();
  final _picker = ImagePicker();
  bool _loading = false;
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _expCtrl     = TextEditingController();
  final _bioCtrl     = TextEditingController();
  List<dynamic> _zones = [];
  final Set<int> _selectedZones = {};
  File? _profileImg, _idProof;

  @override
  void initState() { super.initState(); _loadZones(); }

  Future<void> _loadZones() async {
    try {
      final res = await _api.getZones();
      if (mounted) setState(() => _zones = res is List ? res : []);
    } catch (_) {}
  }

  Future<void> _pickImage(bool isProfile) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f != null) setState(() => isProfile ? _profileImg = File(f.path) : _idProof = File(f.path));
  }

  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (name.isEmpty)       { showAppToast(context, 'Name is required', isError: true); return; }
    if (phone.length != 10) { showAppToast(context, 'Enter valid 10-digit phone', isError: true); return; }

    setState(() => _loading = true);
    try {
      await _api.registerGardener(
        name: name, phone: phone,
        email: _emailCtrl.text.isNotEmpty ? _emailCtrl.text.trim() : null,
        bio: _bioCtrl.text.isNotEmpty ? _bioCtrl.text.trim() : null,
        experienceYears: int.tryParse(_expCtrl.text),
        serviceZoneIds: _selectedZones.toList(),
        profileImage: _profileImg, idProof: _idProof,
      );
      if (mounted) {
        showAppToast(context, 'Application submitted! Admin will review within 24 hours.', isSuccess: true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _expCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('Apply as Gardener'),
        backgroundColor: AppColors.forest,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 40),
        child: Column(children: [
          // Profile photo
          Center(child: GestureDetector(
            onTap: () => _pickImage(true),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgSubtle,
                border: Border.all(color: _profileImg != null ? AppColors.forest : AppColors.border, width: 2),
                image: _profileImg != null ? DecorationImage(image: FileImage(_profileImg!), fit: BoxFit.cover) : null,
              ),
              child: _profileImg == null ? const Icon(Icons.add_a_photo_rounded, size: 28, color: AppColors.textFaint) : null,
            ),
          ).animate().scale(duration: 300.ms, curve: Curves.elasticOut)),
          const SizedBox(height: 6),
          Text('Profile Photo', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 24),

          PremiumCard(padding: const EdgeInsets.all(20), child: Column(children: [
            _Field(label: 'Full Name *', controller: _nameCtrl, hint: 'Your full name'),
            const SizedBox(height: 14),
            _Field(label: 'Phone Number *', controller: _phoneCtrl, hint: '10-digit mobile', keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
            const SizedBox(height: 14),
            _Field(label: 'Email', controller: _emailCtrl, hint: 'your@email.com', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _Field(label: 'Experience (years)', controller: _expCtrl, hint: 'e.g. 3', keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            _Field(label: 'Bio / About You', controller: _bioCtrl, hint: 'Tell us about your gardening experience...', maxLines: 3),
          ])).animate().fadeIn(duration: 300.ms),

          // Zones
          if (_zones.isNotEmpty) ...[
            const SizedBox(height: 14),
            PremiumCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Service Zones', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 4),
              Text('Select areas where you can work', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: _zones.map<Widget>((z) {
                final sel = _selectedZones.contains(z['id'] as int? ?? 0);
                return GestureDetector(
                  onTap: () => setState(() => sel ? _selectedZones.remove(z['id']) : _selectedZones.add(z['id'] as int)),
                  child: AnimatedContainer(
                    duration: 150.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.forest : AppColors.bgSubtle,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: sel ? AppColors.forest : AppColors.border),
                    ),
                    child: Text(z['name'] ?? '—', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.white : AppColors.text2)),
                  ),
                );
              }).toList()),
            ])).animate().fadeIn(delay: 100.ms),
          ],

          // ID Proof
          const SizedBox(height: 14),
          PremiumCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ID Proof', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Text('Aadhaar, PAN or Driving License', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _pickImage(false),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _idProof != null ? AppColors.forest : AppColors.border, style: BorderStyle.solid),
                  image: _idProof != null ? DecorationImage(image: FileImage(_idProof!), fit: BoxFit.cover) : null,
                ),
                child: _idProof == null ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.upload_file_rounded, size: 22, color: AppColors.textFaint),
                  const SizedBox(width: 8),
                  Text('Upload ID Document', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted)),
                ]) : null,
              ),
            ),
          ])).animate().fadeIn(delay: 150.ms),

          const SizedBox(height: 24),
          GkmButton(label: 'Submit Application', loading: _loading, onTap: _submit).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Center(child: Text('Admin will review and approve within 24 hours',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textFaint))),
        ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  const _Field({required this.label, required this.controller, required this.hint, this.maxLines = 1, this.keyboardType, this.inputFormatters});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
    const SizedBox(height: 6),
    TextField(
      controller: controller, maxLines: maxLines,
      keyboardType: keyboardType, inputFormatters: inputFormatters,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
      decoration: InputDecoration(hintText: hint),
    ),
  ]);
}
