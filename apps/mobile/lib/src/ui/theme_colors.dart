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
