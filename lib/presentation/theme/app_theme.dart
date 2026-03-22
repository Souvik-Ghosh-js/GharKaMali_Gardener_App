import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand palette from design spec
  static const Color forest     = Color(0xFF03411A);
  static const Color forestMid  = Color(0xFF054D20);
  static const Color forestLight= Color(0xFF0A5C28);
  static const Color gold       = Color(0xFFEDCF87);
  static const Color goldDark   = Color(0xFFD4B96A);
  static const Color sage       = Color(0xFF808285);
  static const Color earth      = Color(0xFF96794F);
  static const Color cream      = Color(0xFFFFF9E1);

  // Surface
  static const Color bg         = Color(0xFFF0F4EE);
  static const Color bgCard     = Color(0xFFFFFFFF);
  static const Color bgSubtle   = Color(0xFFEDF2EB);
  static const Color border     = Color(0xFFDDE8D9);
  static const Color borderLight= Color(0xFFEEF4EA);

  // Text
  static const Color text       = Color(0xFF111A0F);
  static const Color text2      = Color(0xFF3D4A39);
  static const Color textMuted  = Color(0xFF6B7C66);
  static const Color textFaint  = Color(0xFF9AAA94);

  // Status
  static const Color success    = Color(0xFF16A34A);
  static const Color error      = Color(0xFFDC2626);
  static const Color warning    = Color(0xFFD97706);
  static const Color info       = Color(0xFF2563EB);

  // Status bg/text pairs
  static Color statusBg(String status) {
    switch (status) {
      case 'assigned':    return info.withOpacity(0.1);
      case 'en_route':    return warning.withOpacity(0.1);
      case 'arrived':     return warning.withOpacity(0.1);
      case 'in_progress': return warning.withOpacity(0.1);
      case 'completed':   return success.withOpacity(0.1);
      case 'cancelled':   return sage.withOpacity(0.12);
      case 'failed':      return error.withOpacity(0.1);
      default:            return sage.withOpacity(0.12);
    }
  }

  static Color statusText(String status) {
    switch (status) {
      case 'assigned':    return const Color(0xFF1D4ED8);
      case 'en_route':    return const Color(0xFF92400E);
      case 'arrived':     return const Color(0xFF92400E);
      case 'in_progress': return const Color(0xFF92400E);
      case 'completed':   return const Color(0xFF14532D);
      case 'cancelled':   return const Color(0xFF6B7280);
      case 'failed':      return const Color(0xFF7F1D1D);
      default:            return const Color(0xFF6B7280);
    }
  }
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forest,
        primary: AppColors.forest,
        secondary: AppColors.gold,
        surface: AppColors.bgCard,
        background: AppColors.bg,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
        displayLarge:  GoogleFonts.poppins(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: AppColors.text),
        displayMedium: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: AppColors.text),
        headlineLarge: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.text),
        headlineMedium:GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.text),
        titleLarge:    GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
        titleMedium:   GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
        titleSmall:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text2),
        bodyLarge:     GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.text2),
        bodyMedium:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.text2),
        bodySmall:     GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textMuted),
        labelLarge:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall:    GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.poppins(color: AppColors.textFaint, fontSize: 14),
        labelStyle: GoogleFonts.poppins(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          side: const BorderSide(color: AppColors.forest, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1, space: 0),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// Shadow helpers
List<BoxShadow> cardShadow() => [
  BoxShadow(color: AppColors.forest.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
];
List<BoxShadow> elevatedShadow() => [
  BoxShadow(color: AppColors.forest.withOpacity(0.12), blurRadius: 32, offset: const Offset(0, 8)),
];
