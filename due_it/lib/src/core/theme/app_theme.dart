import 'package:flutter/material.dart';

/// Available app themes in DueIt
enum AppThemeKey {
  modernLavender,
  calmMint,
  skyBlue,
  warmPeach,
  elegantDark,
  minimalNeutral,
}

extension AppThemeKeyExtension on AppThemeKey {
  String get id => name;

  String get displayName {
    switch (this) {
      case AppThemeKey.modernLavender:
        return 'Modern Lavender';
      case AppThemeKey.calmMint:
        return 'Calm Mint';
      case AppThemeKey.skyBlue:
        return 'Sky Blue';
      case AppThemeKey.warmPeach:
        return 'Warm Peach';
      case AppThemeKey.elegantDark:
        return 'Elegant Dark';
      case AppThemeKey.minimalNeutral:
        return 'Minimal Neutral';
    }
  }

  String get description {
    switch (this) {
      case AppThemeKey.modernLavender:
        return 'Refined purple & violet accents with clean surface cards';
      case AppThemeKey.calmMint:
        return 'Fresh mint & emerald tones for clarity and tranquility';
      case AppThemeKey.skyBlue:
        return 'Vibrant cerulean & ocean blues for a focused workspace';
      case AppThemeKey.warmPeach:
        return 'Soft peach, coral & terracotta warmth';
      case AppThemeKey.elegantDark:
        return 'Sophisticated deep obsidian dark mode with violet contrast';
      case AppThemeKey.minimalNeutral:
        return 'Clean slate, crisp monochrome typography and gentle borders';
    }
  }

  Color get previewColor {
    switch (this) {
      case AppThemeKey.modernLavender:
        return const Color(0xFF6750A4);
      case AppThemeKey.calmMint:
        return const Color(0xFF0F766E);
      case AppThemeKey.skyBlue:
        return const Color(0xFF0284C7);
      case AppThemeKey.warmPeach:
        return const Color(0xFFEA580C);
      case AppThemeKey.elegantDark:
        return const Color(0xFF18181B);
      case AppThemeKey.minimalNeutral:
        return const Color(0xFF475569);
    }
  }

  static AppThemeKey fromId(String? id) {
    if (id == null) return AppThemeKey.modernLavender;
    for (final key in AppThemeKey.values) {
      if (key.name == id) return key;
    }
    return AppThemeKey.modernLavender;
  }
}

/// Unified Design System & Themes for DueIt
class AppTheme {
  // Common elevation and radius constants
  static const double cardRadius = 16.0;
  static const double inputRadius = 12.0;
  static const double buttonRadius = 12.0;

  static ThemeData getTheme(AppThemeKey themeKey) {
    switch (themeKey) {
      case AppThemeKey.modernLavender:
        return _buildTheme(
          primary: const Color(0xFF6750A4),
          secondary: const Color(0xFF8B5CF6),
          tertiary: const Color(0xFF7D5260),
          brightness: Brightness.light,
          surface: const Color(0xFFFBFBFE),
          cardColor: Colors.white,
          scaffoldBg: const Color(0xFFF7F6FC),
        );
      case AppThemeKey.calmMint:
        return _buildTheme(
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF14B8A6),
          tertiary: const Color(0xFF059669),
          brightness: Brightness.light,
          surface: const Color(0xFFF7FCFA),
          cardColor: Colors.white,
          scaffoldBg: const Color(0xFFF0FDF4),
        );
      case AppThemeKey.skyBlue:
        return _buildTheme(
          primary: const Color(0xFF0284C7),
          secondary: const Color(0xFF38BDF8),
          tertiary: const Color(0xFF2563EB),
          brightness: Brightness.light,
          surface: const Color(0xFFF8FAFC),
          cardColor: Colors.white,
          scaffoldBg: const Color(0xFFF0F9FF),
        );
      case AppThemeKey.warmPeach:
        return _buildTheme(
          primary: const Color(0xFFEA580C),
          secondary: const Color(0xFFFB923C),
          tertiary: const Color(0xFFDB2777),
          brightness: Brightness.light,
          surface: const Color(0xFFFFFBF9),
          cardColor: Colors.white,
          scaffoldBg: const Color(0xFFFFF7ED),
        );
      case AppThemeKey.elegantDark:
        return _buildTheme(
          primary: const Color(0xFFD0BCFF),
          secondary: const Color(0xFFA78BFA),
          tertiary: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
          surface: const Color(0xFF18181B),
          cardColor: const Color(0xFF202026),
          scaffoldBg: const Color(0xFF111114),
        );
      case AppThemeKey.minimalNeutral:
        return _buildTheme(
          primary: const Color(0xFF334155),
          secondary: const Color(0xFF64748B),
          tertiary: const Color(0xFF475569),
          brightness: Brightness.light,
          surface: const Color(0xFFFAFAFA),
          cardColor: Colors.white,
          scaffoldBg: const Color(0xFFF1F5F9),
        );
    }
  }

  static ThemeData _buildTheme({
    required Color primary,
    required Color secondary,
    required Color tertiary,
    required Brightness brightness,
    required Color surface,
    required Color cardColor,
    required Color scaffoldBg,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      cardColor: cardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1E1B26),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xFF1E1B26),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: isDark ? 0 : 0.8,
        shadowColor: isDark
            ? Colors.transparent
            : Colors.black.withOpacity(0.06),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark ? const Color(0xFF2D2D35) : const Color(0xFFE9E8EE),
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? const Color(0xFF1A1A22) : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? const Color(0xFF1A1A22) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: isDark ? const Color(0xFF1A1A22) : Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: primary,
        unselectedItemColor: isDark
            ? const Color(0xFF888894)
            : const Color(0xFF6B6E7B),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF3F2F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF33333F) : const Color(0xFFE2E1EA),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2C2C38) : const Color(0xFFE2E1EA),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF2B2B35) : const Color(0xFFEDEDF4),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? const Color(0xFF282833)
            : const Color(0xFFEFEFF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
    );
  }
}
