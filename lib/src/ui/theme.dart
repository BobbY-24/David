import 'package:flutter/material.dart';

class DavidColors {
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

ThemeData davidTheme() {
  const scheme = ColorScheme.dark(
    surface: DavidColors.panel,
    primary: DavidColors.amber,
    onPrimary: DavidColors.amberInk,
    secondary: DavidColors.sage,
    onSecondary: DavidColors.amberInk,
    error: DavidColors.coral,
    onSurface: DavidColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DavidColors.bg,
    colorScheme: scheme,
    dividerColor: DavidColors.line,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: DavidColors.ink,
      displayColor: DavidColors.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DavidColors.amber,
        foregroundColor: DavidColors.amberInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DavidColors.ink,
        side: const BorderSide(color: DavidColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DavidColors.bg,
      hintStyle: const TextStyle(color: DavidColors.faint),
      labelStyle: const TextStyle(color: DavidColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DavidColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DavidColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DavidColors.amber),
      ),
    ),
  );
}
