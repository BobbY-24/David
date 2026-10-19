import 'package:flutter/material.dart';

class FieldlineColors {
  static const bg = Color(0xFF101410);
  static const panel = Color(0xFF18201B);
  static const panelRaised = Color(0xFF212A24);
  static const line = Color(0xFF314038);
  static const ink = Color(0xFFEBE6DA);
  static const muted = Color(0xFFA8B1A4);
  static const faint = Color(0xFF6E786F);
  static const amber = Color(0xFFE0A045);
  static const amberInk = Color(0xFF1C1408);
  static const sage = Color(0xFF8FBF9F);
  static const coral = Color(0xFFE07A5F);
  static const mist = Color(0xFF8EB4C8);
  static const memo = Color(0xFFF4F0E6);
  static const memoInk = Color(0xFF1C2118);
  static const memoMuted = Color(0xFF5C6558);
  static const memoRule = Color(0xFFD9D2C3);
}

ThemeData fieldlineTheme() {
  const scheme = ColorScheme.dark(
    surface: FieldlineColors.panel,
    primary: FieldlineColors.amber,
    onPrimary: FieldlineColors.amberInk,
    secondary: FieldlineColors.sage,
    onSecondary: FieldlineColors.amberInk,
    error: FieldlineColors.coral,
    onSurface: FieldlineColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FieldlineColors.bg,
    colorScheme: scheme,
    dividerColor: FieldlineColors.line,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: FieldlineColors.ink,
      displayColor: FieldlineColors.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FieldlineColors.amber,
        foregroundColor: FieldlineColors.amberInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FieldlineColors.ink,
        side: const BorderSide(color: FieldlineColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FieldlineColors.bg,
      hintStyle: const TextStyle(color: FieldlineColors.faint),
      labelStyle: const TextStyle(color: FieldlineColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FieldlineColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FieldlineColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FieldlineColors.amber),
      ),
    ),
  );
}
