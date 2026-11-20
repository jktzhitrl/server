import 'package:flutter/material.dart';

/// Dunkles Design mit grünen Akzenten (Darts-Turniersoftware-Stil).
class AppColors {
  static const background = Color(0xFF0A0E0B);
  static const surface = Color(0xFF121915);
  static const surfaceHigh = Color(0xFF1A241E);
  static const accent = Color(0xFF2ECC71);
  static const accentDim = Color(0xFF1E8449);
  static const warning = Color(0xFFF5B041);
  static const danger = Color(0xFFE74C3C);
  static const textDim = Color(0xFF9DB0A3);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.black,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF22302A)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accentDim,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accentDim,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    dividerColor: const Color(0xFF22302A),
  );
}

/// Große, gut lesbare Ziffern mit festen Ziffernbreiten.
const TextStyle bigNumber = TextStyle(
  fontWeight: FontWeight.w800,
  fontFeatures: [FontFeature.tabularFigures()],
  height: 1.0,
);
