import 'package:flutter/material.dart';

import '../data/library_store.dart';

Color seedColorForAccent(AppAccentColor accentColor) {
  switch (accentColor) {
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
