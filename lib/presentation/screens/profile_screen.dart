import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLoggedOut;
  const ProfileScreen({super.key, required this.onLoggedOut});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _profile;
  bool _loading = true, _editing = false, _saving = false;

  final _bioCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _bankNameCtrl    = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankIfscCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    _expCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getGardenerProfile();
      if (mounted) {
        _profile = res is Map<String,dynamic> ? res : {};
        final gp = _profile!['gardenerProfile'] as Map<String,dynamic>? ?? {};
        _bioCtrl.text        = gp['bio'] ?? '';
        _expCtrl.text        = (gp['experience_years'] ?? '').toString();
        _bankNameCtrl.text    = gp['bank_name'] ?? '';
        _bankAccountCtrl.text = gp['bank_account'] ?? '';
        _bankIfscCtrl.text    = gp['bank_ifsc'] ?? '';
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.updateGardenerProfile({
        'bio': _bioCtrl.text,
        'experience_years': int.tryParse(_expCtrl.text) ?? 0,
        'bank_name': _bankNameCtrl.text,
        'bank_account': _bankAccountCtrl.text,
        'bank_ifsc': _bankIfscCtrl.text,
      });
      await _load();
      if (mounted) {
        setState(() {
          _editing = false;
          _saving = false;
        });
        showAppToast(context, 'Profile updated!', isSuccess: true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppToast(context, e.message, isError: true);
      }
    }
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textMuted))
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Sign Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.error))
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      widget.onLoggedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};
    final gp = (_profile?['gardenerProfile'] ?? user['gardenerProfile']) as Map<String,dynamic>? ?? {};
    final zones = (gp['zones'] as List?) ?? [];
    final name = _profile?['name'] ?? user['name'] ?? 'Gardener';
    final phone = _profile?['phone'] ?? user['phone'] ?? '';
    num _toNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }
    final avgRating = _toNum(gp['rating'] ?? gp['avg_rating']);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: GradientHeader(
                bottomPadding: 32,
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                      child: (_profile?['profile_image'] != null)
                          ? ClipOval(child: Image.network(_profile!['profile_image'], fit: BoxFit.cover))
                          : Center(
                          child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'G',
                              style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)
                          )
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              name,
                              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)
                          ).animate().fadeIn(),
                          Text('+91 $phone', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white60)),
                          if ((_profile?['is_approved'] ?? user['is_approved']) == true) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppColors.gold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: AppColors.gold.withOpacity(0.3))
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.gold)
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                      'Approved Gardener',
                                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content with proper padding
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Changed from -24 to 16
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Stats
                  if (_loading)
                    const SkeletonBox(width: double.infinity, height: 80, radius: 20)
                  else
                    Row(
                      children: [
                        Expanded(
                            child: _StatBox(
                                label: 'Rating',
                                value: avgRating > 0 ? '${avgRating.toStringAsFixed(1)} ★' : 'New',
                                color: AppColors.gold
                            )
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _StatBox(
                                label: 'Experience',
                                value: '${gp['experience_years'] ?? 0} yrs',
                                color: AppColors.forest
                            )
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _StatBox(
                                label: 'Jobs Done',
                                value: '${gp['total_jobs'] ?? 0}',
                                color: AppColors.info
                            )
                        ),
                      ],
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0),
                  const SizedBox(height: 14),

                  // Zones
                  if (zones.isNotEmpty) ...[
                    PremiumCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'SERVICE ZONES',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMuted,
                                  letterSpacing: 1
                              )
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: zones.map<Widget>((z) => Container(
                              key: ValueKey(z['id']), // Add key
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                  color: AppColors.forest.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(99)
                              ),
                              child: Text(
                                  z['name'] ?? '—',
                                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.forest)
                              ),
                            )).toList(),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 50.ms),
                    const SizedBox(height: 12),
                  ],

                  // Professional Info
                  PremiumCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                'Details',
                                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)
                            ),
                            if (_editing) ...[
                              Row(
                                key: const ValueKey('edit_actions'),
                                mainAxisSize: MainAxisSize.min, // Add this to prevent overflow
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _editing = false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppColors.border),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                          'Cancel',
                                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox( // Wrap GkmButton in SizedBox to constrain width
                                    width: 120,
                                    height: 34,
                                    child: GkmButton(
                                      key: const ValueKey('save_button'),
                                      label: _saving ? 'Saving…' : 'Save',
                                      loading: _saving,
                                      onTap: _save,
                                      width: 80,
                                      height: 34,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              GestureDetector(
                                key: const ValueKey('edit_button'),
                                onTap: () => setState(() => _editing = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.forest, width: 1.5),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                      'Edit',
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.forest
                                      )
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (_editing) ...[
                          _EditField(label: 'Bio', controller: _bioCtrl, maxLines: 3, hint: 'Your gardening story...'),
                          const SizedBox(height: 12),
                          _EditField(label: 'Experience (years)', controller: _expCtrl, keyboardType: TextInputType.number),
                        ] else ...[
                          if ((gp['bio'] ?? '').isNotEmpty) ...[
                            Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    'BIO',
                                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1)
                                )
                            ),
                            const SizedBox(height: 6),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    gp['bio'].toString(),
                                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2, height: 1.6)
                                )
                            ),
                          ] else
                            const EmptyState(
                                icon: Icons.edit_note_rounded,
                                title: 'No bio yet',
                                subtitle: 'Tap Edit to add your profile info'
                            ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 12),

                  // Bank Details
                  PremiumCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.forest),
                            const SizedBox(width: 8),
                            Text(
                                'Bank Details',
                                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)
                            ),
                            const Spacer(),
                            Text(
                                '(for payouts)',
                                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textFaint)
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_editing) ...[
                          _EditField(label: 'Bank Name', controller: _bankNameCtrl),
                          const SizedBox(height: 12),
                          _EditField(label: 'Account Number', controller: _bankAccountCtrl, keyboardType: TextInputType.number),
                          const SizedBox(height: 12),
                          _EditField(label: 'IFSC Code', controller: _bankIfscCtrl),
                        ] else ...[
                          if ((gp['bank_name'] ?? '').isNotEmpty) ...[
                            _BankRow(label: 'Bank', value: gp['bank_name'].toString()),
                            _BankRow(label: 'Account', value: _maskAccount(gp['bank_account']?.toString() ?? '')),
                            _BankRow(label: 'IFSC', value: gp['bank_ifsc']?.toString() ?? '—'),
                          ] else
                            Text(
                                'No bank details added yet. Tap Edit to add.',
                                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textFaint)
                            ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 20),

                  // Logout
                  GkmButton(
                      label: 'Sign Out',
                      icon: Icons.logout_rounded,
                      onTap: _logout,
                      outline: true,
                      danger: true
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                        'Developed by Gobt',
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textFaint)
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _maskAccount(String acc) {
    if (acc.length < 4) return acc;
    return '•' * (acc.length - 4) + acc.substring(acc.length - 4);
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: cardShadow()
    ),
    child: Column(
      children: [
        Text(
            value,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5
            )
        ),
        const SizedBox(height: 3),
        Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600
            )
        ),
      ],
    ),
  );
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboardType;
  const _EditField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.hint,
    this.keyboardType
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text2),
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );
}

class _BankRow extends StatelessWidget {
  final String label, value;
  const _BankRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)
          ),
        ),
        Expanded(
          child: Text(
              value,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)
          ),
        ),
      ],
    ),
  );
}