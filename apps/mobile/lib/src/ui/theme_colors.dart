import 'package:flutter/material.dart';

import '../data/library_store.dart';

Color seedColorForAccent(AppAccentColor accentColor) {
  switch (accentColor) {
    case AppAccentColor.system:
      return Colors.indigo;
    case AppAccentColor.indigo:
      return Colors.indigo;
    case AppAccentColor.teal:
      return Colors.teal;
    case AppAccentColor.rose:
      return Colors.pink;
    case AppAccentColor.amber:
      return Colors.amber;
    case AppAccentColor.violet:
      return Colors.deepPurple;
    case AppAccentColor.green:
      return Colors.green;
  }
}

bool usesSystemAccent(AppAccentColor accentColor) {
  return accentColor == AppAccentColor.system;
}

ColorScheme lightColorSchemeForAccent(
  AppAccentColor accentColor, {
  ColorScheme? dynamicColorScheme,
}) {
  if (usesSystemAccent(accentColor) && dynamicColorScheme != null) {
    return dynamicColorScheme;
  }
  return ColorScheme.fromSeed(
    seedColor: seedColorForAccent(accentColor),
    brightness: Brightness.light,
  );
}

ColorScheme darkColorSchemeForAccent(
  AppAccentColor accentColor, {
  ColorScheme? dynamicColorScheme,
}) {
  if (usesSystemAccent(accentColor) && dynamicColorScheme != null) {
    return dynamicColorScheme;
  }
  return ColorScheme.fromSeed(
    seedColor: seedColorForAccent(accentColor),
    brightness: Brightness.dark,
  );
}

/// Builds the black-surface Material theme used for the AMOLED preference.
///
/// Accent colors remain available for actions and selection while resting
/// surfaces use intentionally distinct near-black layers for legibility.
ThemeData amoledThemeForAccent(
  AppAccentColor accentColor, {
  ColorScheme? dynamicColorScheme,
  VisualDensity visualDensity = VisualDensity.standard,
}) {
  final colorScheme = darkColorSchemeForAccent(
    accentColor,
    dynamicColorScheme: dynamicColorScheme,
  ).copyWith(
    surface: Colors.black,
    surfaceDim: Colors.black,
    surfaceBright: const Color(0xFF181818),
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: const Color(0xFF050505),
    surfaceContainer: const Color(0xFF090909),
    surfaceContainerHigh: const Color(0xFF0E0E0E),
    surfaceContainerHighest: const Color(0xFF151515),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
    cardTheme: CardThemeData(color: colorScheme.surfaceContainerLow),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      modalBackgroundColor: colorScheme.surfaceContainer,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerHigh,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.black,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.black,
    ),
    visualDensity: visualDensity,
  );
}
