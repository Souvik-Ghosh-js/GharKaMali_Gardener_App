import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _api = ApiService();
  String _step = 'phone'; // phone | otp
  final _phoneCtrl = TextEditingController();
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpFocus  = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _countdown = 0;

  void _startTimer() {
    setState(() => _countdown = 30);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length != 10) { showAppToast(context, 'Enter a valid 10-digit number', isError: true); return; }
    setState(() => _loading = true);
    try {
      await _api.sendOtp(phone);
      setState(() { _step = 'otp'; _loading = false; });
      _startTimer();
      showAppToast(context, 'OTP sent to +91 $phone', isSuccess: true);
      Future.delayed(50.ms, () => _otpFocus[0].requestFocus());
    } on ApiException catch (e) {
      setState(() => _loading = false);
      if (mounted) showAppToast(context, e.message, isError: true);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length != 6) return;
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _loading = true);
    try {
      final res = await _api.gardenerLogin(phone, otp);
      final auth = context.read<AuthProvider>();
      await auth.login(res['user'] ?? res, res['token'] ?? '');
      if (mounted) widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => _loading = false);
      for (final c in _otpCtrls) c.clear();
      _otpFocus[0].requestFocus();
      if (mounted) showAppToast(context, e.message, isError: true);
    }
  }

  void _onOtpKey(int i, String value) {
    if (value.isEmpty) {
      if (i > 0) { _otpFocus[i - 1].requestFocus(); }
      return;
    }
    if (i < 5) {
      _otpFocus[i + 1].requestFocus();
    } else {
      _otpFocus[i].unfocus();
      _verifyOtp();
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        // Green top swoosh
        Positioned(
          top: 0, left: 0, right: 0,
          height: MediaQuery.of(context).size.height * 0.42,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.forest, AppColors.forestMid, AppColors.forestLight],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft:  Radius.elliptical(300, 100),
                bottomRight: Radius.elliptical(300, 100),
              ),
            ),
            child: Stack(children: [
              Positioned(top: -30, right: -30, child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold.withOpacity(0.05)),
              )),
              SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.eco_rounded, color: AppColors.gold, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('GKM Gardener', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text('Ghar Ka Mali', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white54)),
                    ]),
                  ]),
                  const SizedBox(height: 32),
                  Text(
                    _step == 'phone' ? 'Welcome Back!' : 'Enter OTP',
                    style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 6),
                  Text(
                    _step == 'phone'
                        ? 'Sign in to manage your garden jobs'
                        : 'Sent to +91 ${_phoneCtrl.text}',
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.white60),
                  ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                ]),
              )),
            ]),
          ),
        ),

        // Card
        Positioned(
          top: MediaQuery.of(context).size.height * 0.34,
          left: 16, right: 16,
          bottom: 0,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: elevatedShadow(),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
                  child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim), child: child)),
                child: _step == 'phone' ? _buildPhoneStep() : _buildOtpStep(),
              ),
            ),
          ).animate().slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic, duration: 500.ms).fadeIn(duration: 400.ms),
        ),
      ]),
    );
  }

  Widget _buildPhoneStep() {
    return Column(key: const ValueKey('phone'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Phone Number', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: AppColors.bgSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
              color: AppColors.bgCard,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
            ),
            child: Text('+91', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text2)),
          ),
          Expanded(child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onSubmitted: (_) => _sendOtp(),
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2),
            decoration: const InputDecoration(
              border: InputBorder.none, focusedBorder: InputBorder.none, enabledBorder: InputBorder.none,
              hintText: '98765 43210', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              hintStyle: TextStyle(letterSpacing: 0, fontWeight: FontWeight.w400, fontSize: 15, color: AppColors.textFaint),
            ),
          )),
        ]),
      ),
      const SizedBox(height: 24),
      GkmButton(label: 'Send OTP', loading: _loading, onTap: _sendOtp),
      const SizedBox(height: 16),
      Center(child: TextButton(
        onPressed: () => Navigator.pushNamed(context, '/register'),
        child: RichText(text: TextSpan(
          text: "New gardener? ", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
          children: [TextSpan(text: 'Apply here', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.forest))],
        )),
      )),
    ]);
  }

  Widget _buildOtpStep() {
    return Column(key: const ValueKey('otp'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () { setState(() { _step = 'phone'; for (final c in _otpCtrls) c.clear(); }); },
        child: Row(children: [
          const Icon(Icons.arrow_back_ios_rounded, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('Change number', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ]),
      ),
      const SizedBox(height: 24),
      Text('6-digit code', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 12),

// Fixed width OTP fields with SingleChildScrollView for small screens
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Container(
              width: 48,
              margin: EdgeInsets.only(right: i < 5 ? 8 : 0),
              child: TextFormField(
                controller: _otpCtrls[i],
                focusNode: _otpFocus[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.text),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)
                  ),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)
                  ),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.forest, width: 2)
                  ),
                  filled: true,
                  fillColor: _otpCtrls[i].text.isNotEmpty
                      ? AppColors.forest.withOpacity(0.04)
                      : AppColors.bgSubtle,
                ),
                onChanged: (v) => _onOtpKey(i, v),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: 24),
      GkmButton(label: 'Verify & Continue', loading: _loading, onTap: _verifyOtp),
      const SizedBox(height: 16),
      Center(child: _countdown > 0
          ? Text('Resend OTP in ${_countdown}s', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted))
          : TextButton(
              onPressed: _sendOtp,
              child: Text('Resend OTP', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.forest)),
            )),
    ]);
  }
}
