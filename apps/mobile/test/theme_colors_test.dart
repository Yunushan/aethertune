import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/theme_colors.dart';

void main() {
  test('maps app accent choices to Material seed colors', () {
    expect(seedColorForAccent(AppAccentColor.system), Colors.indigo);
    expect(seedColorForAccent(AppAccentColor.indigo), Colors.indigo);
    expect(seedColorForAccent(AppAccentColor.teal), Colors.teal);
    expect(seedColorForAccent(AppAccentColor.rose), Colors.pink);
    expect(seedColorForAccent(AppAccentColor.amber), Colors.amber);
    expect(seedColorForAccent(AppAccentColor.violet), Colors.deepPurple);
    expect(seedColorForAccent(AppAccentColor.green), Colors.green);
  });

  test('uses a platform scheme only for the System colors accent', () {
    final dynamicLight = ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: Brightness.light,
    );
    final dynamicDark = ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: Brightness.dark,
    );

    expect(
      lightColorSchemeForAccent(
        AppAccentColor.system,
        dynamicColorScheme: dynamicLight,
      ),
      same(dynamicLight),
    );
    expect(
      darkColorSchemeForAccent(
        AppAccentColor.system,
        dynamicColorScheme: dynamicDark,
      ),
      same(dynamicDark),
    );
    expect(
      lightColorSchemeForAccent(
        AppAccentColor.teal,
        dynamicColorScheme: dynamicLight,
      ),
      ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      ),
    );
    expect(
      darkColorSchemeForAccent(
        AppAccentColor.rose,
        dynamicColorScheme: dynamicDark,
      ),
      ColorScheme.fromSeed(
        seedColor: Colors.pink,
        brightness: Brightness.dark,
      ),
    );
  });

  test('falls back safely when a platform has no dynamic scheme', () {
    expect(usesSystemAccent(AppAccentColor.system), isTrue);
    expect(usesSystemAccent(AppAccentColor.indigo), isFalse);
    expect(
      darkColorSchemeForAccent(AppAccentColor.system),
      ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    );
  });
}
