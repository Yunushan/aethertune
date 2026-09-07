import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as material_ui;

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

/// Converts the dynamic_color package's Material UI scheme to Flutter's scheme.
///
/// dynamic_color 2.x uses the extracted Material UI package, while the app
/// still builds its themes with Flutter's Material library. Both schemes use
/// the same dart:ui colors, so copying the roles preserves the platform palette
/// without mixing the two ColorScheme types.
ColorScheme? flutterColorSchemeFromDynamicColor(
  material_ui.ColorScheme? dynamicColorScheme,
) {
  if (dynamicColorScheme == null) {
    return null;
  }

  return ColorScheme(
    brightness: dynamicColorScheme.brightness,
    primary: dynamicColorScheme.primary,
    onPrimary: dynamicColorScheme.onPrimary,
    primaryContainer: dynamicColorScheme.primaryContainer,
    onPrimaryContainer: dynamicColorScheme.onPrimaryContainer,
    primaryFixed: dynamicColorScheme.primaryFixed,
    primaryFixedDim: dynamicColorScheme.primaryFixedDim,
    onPrimaryFixed: dynamicColorScheme.onPrimaryFixed,
    onPrimaryFixedVariant: dynamicColorScheme.onPrimaryFixedVariant,
    secondary: dynamicColorScheme.secondary,
    onSecondary: dynamicColorScheme.onSecondary,
    secondaryContainer: dynamicColorScheme.secondaryContainer,
    onSecondaryContainer: dynamicColorScheme.onSecondaryContainer,
    secondaryFixed: dynamicColorScheme.secondaryFixed,
    secondaryFixedDim: dynamicColorScheme.secondaryFixedDim,
    onSecondaryFixed: dynamicColorScheme.onSecondaryFixed,
    onSecondaryFixedVariant: dynamicColorScheme.onSecondaryFixedVariant,
    tertiary: dynamicColorScheme.tertiary,
    onTertiary: dynamicColorScheme.onTertiary,
    tertiaryContainer: dynamicColorScheme.tertiaryContainer,
    onTertiaryContainer: dynamicColorScheme.onTertiaryContainer,
    tertiaryFixed: dynamicColorScheme.tertiaryFixed,
    tertiaryFixedDim: dynamicColorScheme.tertiaryFixedDim,
    onTertiaryFixed: dynamicColorScheme.onTertiaryFixed,
    onTertiaryFixedVariant: dynamicColorScheme.onTertiaryFixedVariant,
    error: dynamicColorScheme.error,
    onError: dynamicColorScheme.onError,
    errorContainer: dynamicColorScheme.errorContainer,
    onErrorContainer: dynamicColorScheme.onErrorContainer,
    surface: dynamicColorScheme.surface,
    onSurface: dynamicColorScheme.onSurface,
    surfaceDim: dynamicColorScheme.surfaceDim,
    surfaceBright: dynamicColorScheme.surfaceBright,
    surfaceContainerLowest: dynamicColorScheme.surfaceContainerLowest,
    surfaceContainerLow: dynamicColorScheme.surfaceContainerLow,
    surfaceContainer: dynamicColorScheme.surfaceContainer,
    surfaceContainerHigh: dynamicColorScheme.surfaceContainerHigh,
    surfaceContainerHighest: dynamicColorScheme.surfaceContainerHighest,
    onSurfaceVariant: dynamicColorScheme.onSurfaceVariant,
    outline: dynamicColorScheme.outline,
    outlineVariant: dynamicColorScheme.outlineVariant,
    shadow: dynamicColorScheme.shadow,
    scrim: dynamicColorScheme.scrim,
    inverseSurface: dynamicColorScheme.inverseSurface,
    onInverseSurface: dynamicColorScheme.onInverseSurface,
    inversePrimary: dynamicColorScheme.inversePrimary,
    surfaceTint: dynamicColorScheme.surfaceTint,
  );
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
  final colorScheme =
      darkColorSchemeForAccent(
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
    popupMenuTheme: PopupMenuThemeData(color: colorScheme.surfaceContainerHigh),
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
