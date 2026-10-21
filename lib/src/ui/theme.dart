import 'package:flutter/material.dart';

class DavidColors {
  static const bg = Color(0xFF0A1424);
  static const panel = Color(0xFF102038);
  static const panelRaised = Color(0xFF16294A);
  static const line = Color(0xFF24395C);
  static const ink = Color(0xFFE8ECF2);
  static const muted = Color(0xFF9AA8BC);
  static const faint = Color(0xFF66758C);
  static const brass = Color(0xFFC9A45C);
  static const brassInk = Color(0xFF14100A);
  static const positive = Color(0xFF3FA57A);
  static const negative = Color(0xFFD25B5B);
  static const steel = Color(0xFF7FA6D6);
  static const memo = Color(0xFFFAFAF7);
  static const memoInk = Color(0xFF0B1424);
  static const memoMuted = Color(0xFF55627A);
  static const memoRule = Color(0xFFD8DCE3);
}

ThemeData davidTheme() {
  const scheme = ColorScheme.dark(
    surface: DavidColors.panel,
    primary: DavidColors.brass,
    onPrimary: DavidColors.brassInk,
    secondary: DavidColors.positive,
    onSecondary: DavidColors.brassInk,
    error: DavidColors.negative,
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
        backgroundColor: DavidColors.brass,
        foregroundColor: DavidColors.brassInk,
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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DavidColors.brass
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return DavidColors.faint;
          }
          return states.contains(WidgetState.selected)
              ? DavidColors.brassInk
              : DavidColors.ink;
        }),
        side: const WidgetStatePropertyAll(BorderSide(color: DavidColors.line)),
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
        borderSide: const BorderSide(color: DavidColors.brass),
      ),
    ),
  );
}
