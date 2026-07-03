import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Alongside's visual identity: "Quiet Harbor" - grounded teals and a warm
/// coral accent on a cool pale mist background. Deliberately not the
/// warm-cream-plus-terracotta combination that's become a generic
/// "AI wellness app" default - this app needs to feel calm and held,
/// not templated.
///
/// These are mutable (not `const`) on purpose: [setDark] swaps every value
/// in place so the whole app can flip between light and dark without each
/// screen needing to know which mode is active - they just keep reading
/// `AppColors.tide` etc. as normal. `harbor` is the one exception: it's used
/// as a literal background for chrome elements (sidebar, dark cards) that
/// stay the same deep teal in both modes by design, so it isn't part of the
/// swap. Heading text color is a separate token ([headingText]) precisely
/// so it can flip to a light color in dark mode without touching `harbor`.
class AppColors {
  AppColors._();

  static Color mist = const Color(0xFFF2F6F4); // base background
  static Color surface = const Color(0xFFFFFFFF); // cards, sheets, inputs
  static const harbor = Color(0xFF1E3A3F); // chrome bg (sidebar/dark cards) - constant in both modes
  static Color headingText = const Color(0xFF1E3A3F); // heading/title text - flips in dark mode
  static Color tide = const Color(0xFF3E7C74); // primary brand accent
  static Color tideLight = const Color(0xFFDCEAE6); // tide tint for chips/highlights
  static const ember = Color(0xFFE8927C); // warm secondary accent - reads fine on both bg
  static Color charcoal = const Color(0xFF26302F); // body text
  static Color mutedText = const Color(0xFF6B7674); // secondary/caption text
  static Color line = const Color(0xFFE1E7E4); // hairline borders
  static Color alert = const Color(0xFFC24B4B); // crisis / destructive
  static Color alertTint = const Color(0xFFFBEAEA);
  static bool isDark = false;

  static void setDark(bool dark) {
    isDark = dark;
    if (dark) {
      mist = const Color(0xFF13201F);
      surface = const Color(0xFF1C2B2A);
      headingText = const Color(0xFFEAF3F1);
      tide = const Color(0xFF5FAFA0);
      tideLight = const Color(0xFF23413E);
      charcoal = const Color(0xFFDDEAE7);
      mutedText = const Color(0xFF93A6A2);
      line = const Color(0xFF2C3E3C);
      alert = const Color(0xFFE07272);
      alertTint = const Color(0xFF3A2020);
    } else {
      mist = const Color(0xFFF2F6F4);
      surface = const Color(0xFFFFFFFF);
      headingText = const Color(0xFF1E3A3F);
      tide = const Color(0xFF3E7C74);
      tideLight = const Color(0xFFDCEAE6);
      charcoal = const Color(0xFF26302F);
      mutedText = const Color(0xFF6B7674);
      line = const Color(0xFFE1E7E4);
      alert = const Color(0xFFC24B4B);
      alertTint = const Color(0xFFFBEAEA);
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: AppColors.isDark ? Brightness.dark : Brightness.light);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.mist,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.tide,
        onPrimary: Colors.white,
        secondary: AppColors.ember,
        onSecondary: AppColors.harbor,
        surface: AppColors.surface,
        onSurface: AppColors.charcoal,
        error: AppColors.alert,
      ),
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.fraunces(
          fontSize: 40,
          fontWeight: FontWeight.w600,
          color: AppColors.headingText,
          height: 1.1,
        ),
        displayMedium: GoogleFonts.fraunces(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          color: AppColors.headingText,
          height: 1.15,
        ),
        headlineSmall: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.headingText,
        ),
        titleMedium: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.headingText,
        ),
        bodyLarge: GoogleFonts.manrope(fontSize: 16, height: 1.5, color: AppColors.charcoal),
        bodyMedium: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: AppColors.charcoal),
        labelSmall: GoogleFonts.manrope(fontSize: 12, color: AppColors.mutedText),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.mist,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.headingText,
        ),
        iconTheme: IconThemeData(color: AppColors.headingText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.tide,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.tide.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.tide,
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.tide, width: 1.5),
        ),
        labelStyle: GoogleFonts.manrope(color: AppColors.mutedText),
        hintStyle: GoogleFonts.manrope(color: AppColors.mutedText),
      ),
      dividerTheme: DividerThemeData(color: AppColors.line, thickness: 1, space: 32),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.mutedText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.tide : AppColors.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
