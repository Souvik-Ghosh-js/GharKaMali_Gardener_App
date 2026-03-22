import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_theme.dart';

// ── STATUS BADGE ──────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  final bool small;
  const StatusBadge(this.status, {super.key, this.small = false});

  String get label => status.replaceAll('_', ' ').toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusBg(status),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: AppColors.statusText(status),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── PREMIUM CARD ──────────────────────────────────────────────────────────────
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? radius;
  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius ?? BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? AppColors.bgCard,
            borderRadius: radius ?? BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: cardShadow(),
          ),
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

// ── SKELETON LOADER ───────────────────────────────────────────────────────────
class SkeletonBox extends StatelessWidget {
  final double width, height;
  final double radius;
  const SkeletonBox({super.key, required this.width, required this.height, this.radius = 12});
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.bgSubtle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Shimmer.fromColors(
        baseColor: AppColors.border,
        highlightColor: AppColors.bgSubtle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 14, width: double.infinity, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(7))),
              const SizedBox(height: 8),
              Container(height: 11, width: 160, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(5))),
            ])),
          ]),
          const SizedBox(height: 16),
          Container(height: 11, width: double.infinity, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(5))),
          const SizedBox(height: 6),
          Container(height: 11, width: 200, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(5))),
        ]),
      ),
    );
  }
}
// ── GKM BUTTON ────────────────────────────────────────────────────────────────
class GkmButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool outline;
  final bool danger;
  final IconData? icon;
  final Color? color;
  final double? width;
  final double height;
  const GkmButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.outline = false,
    this.danger = false,
    this.icon,
    this.color,
    this.width,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final bg = danger ? AppColors.error : (color ?? AppColors.forest);
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: outline ? Colors.transparent : bg,
          foregroundColor: outline ? bg : Colors.white,
          disabledBackgroundColor: outline ? Colors.transparent : bg.withOpacity(0.5),
          disabledForegroundColor: outline ? bg.withOpacity(0.5) : Colors.white.withOpacity(0.7),
          side: outline ? BorderSide(color: bg, width: 1.5) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced padding
          minimumSize: Size(width ?? 80, height), // Set minimum size
        ),
        child: loading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: outline ? bg : Colors.white,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16), // Reduced icon size
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13, // Reduced from 15
                  fontWeight: FontWeight.w600, // Slightly less bold
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GRADIENT HEADER ───────────────────────────────────────────────────────────
class GradientHeader extends StatelessWidget {
  final Widget child;
  final double bottomPadding;
  const GradientHeader({super.key, required this.child, this.bottomPadding = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forest, AppColors.forestMid, AppColors.forestLight],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
          child: child,
        ),
      ),
    );
  }
}

// ── INFO ROW ──────────────────────────────────────────────────────────────────
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const InfoRow({super.key, required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: AppColors.bgSubtle, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: AppColors.forest),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text2)),
        ])),
      ]),
    );
  }
}

// ── ANIMATED TOAST ────────────────────────────────────────────────────────────
void showAppToast(BuildContext context, String message, {bool isError = false, bool isSuccess = false}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _ToastWidget(
    message: message, isError: isError, isSuccess: isSuccess,
    onDismiss: () => entry.remove(),
  ));
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError, isSuccess;
  final VoidCallback onDismiss;
  const _ToastWidget({required this.message, required this.isError, required this.isSuccess, required this.onDismiss});
  @override State<_ToastWidget> createState() => _ToastWidgetState();
}
class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
    _c.forward();
    Future.delayed(const Duration(milliseconds: 2500), () async {
      if (mounted) { await _c.reverse(); widget.onDismiss(); }
    });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.isError ? AppColors.error : widget.isSuccess ? AppColors.success : AppColors.forest;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16, right: 16,
      child: SlideTransition(position: _slide,
        child: FadeTransition(opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: color, width: 4)),
                boxShadow: elevatedShadow(),
              ),
              child: Row(children: [
                Icon(
                  widget.isError ? Icons.error_outline_rounded
                      : widget.isSuccess ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color: color, size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.message,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text2))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── EMPTY STATE ───────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  const EmptyState({super.key, required this.title, required this.subtitle, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.bgSubtle, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 32, color: AppColors.textFaint),
          ),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted, height: 1.5)),
        ]),
      ),
    );
  }
}

// ── SECTION HEADER ────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.forest)),
        ),
    ]);
  }
}

// ── LOTTIE ICON WRAPPER ───────────────────────────────────────────────────────
class LottieIcon extends StatelessWidget {
  final String assetPath;
  final double size;
  final bool repeat;
  const LottieIcon({super.key, required this.assetPath, this.size = 80, this.repeat = true});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Lottie.asset(
        assetPath, width: size, height: size,
        repeat: repeat, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.eco_rounded, size: size * 0.5, color: AppColors.forest),
      ),
    );
  }
}

// ── LIVE INDICATOR ─────────────────────────────────────────────────────────────
class LiveIndicator extends StatefulWidget {
  final String label;
  const LiveIndicator({super.key, this.label = 'LIVE'});
  @override State<LiveIndicator> createState() => _LiveIndicatorState();
}
class _LiveIndicatorState extends State<LiveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _pulse;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success.withOpacity(_pulse.value),
          boxShadow: [BoxShadow(color: AppColors.success.withOpacity(_pulse.value * 0.5), blurRadius: 6, spreadRadius: 1)],
        ),
      )),
      const SizedBox(width: 6),
      Text(widget.label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800,
          color: AppColors.success, letterSpacing: 1.0)),
    ]);
  }
}