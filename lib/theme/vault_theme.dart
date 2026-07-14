import 'package:flutter/material.dart';

/// Shared design tokens for Vault OS.
///
/// The palette takes its cue from a physical safe — brushed charcoal
/// steel with a brass dial — instead of another green-on-black
/// "hacker terminal" theme. One accent, hairline borders, no shadows.
class VaultTheme {
  VaultTheme._();

  // Surfaces
  static const Color bg = Color(0xFF0B0C0E);
  static const Color surface = Color(0xD9171A1F);
  static const Color surfaceStrong = Color(0xE321252B);
  static const Color surfaceRaised = Color(0xC221252B);
  static const Color border = Color(0xFF343942);
  static const Color borderStrong = Color(0xFF33383F);
  static const Color glassHighlight = Color(0x1FFFFFFF);
  static const Color glassHighlightStrong = Color(0x26FFFFFF);

  // Accent — the brass dial
  static const Color brass = Color(0xFFC9974B);
  static const Color brassBright = Color(0xFFE3B368);

  // Status
  static const Color success = Color(0xFF5FA783);
  static const Color danger = Color(0xFFC1594B);
  static const Color warning = Color(0xFFD3A24C);

  // Text
  static const Color textPrimary = Color(0xFFEDEEF0);
  static const Color textSecondary = Color(0xFFD5DAE2);
  static const Color textMuted = Color(0xFFB0B7C2);

  static const double radius = 10;
  static const double radiusSmall = 6;

  static const TextStyle display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle heading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    color: textSecondary,
    height: 1.45,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    color: textMuted,
    letterSpacing: 0.2,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11.5,
    color: textSecondary,
    letterSpacing: 0.4,
  );

  /// Apply as the app's ThemeData so every default Button/TextField
  /// picks up the compact, hairline-bordered look automatically.
  static ThemeData themeData() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: brass,
        secondary: brassBright,
        surface: surface,
        error: danger,
      ),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: brass, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: danger),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brass,
          foregroundColor: const Color(0xFF1A1200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
    );
  }
}
