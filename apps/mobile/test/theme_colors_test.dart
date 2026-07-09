import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/theme_colors.dart';

void main() {
  test('maps app accent choices to Material seed colors', () {
    expect(seedColorForAccent(AppAccentColor.indigo), Colors.indigo);
    expect(seedColorForAccent(AppAccentColor.teal), Colors.teal);
    expect(seedColorForAccent(AppAccentColor.rose), Colors.pink);
    expect(seedColorForAccent(AppAccentColor.amber), Colors.amber);
    expect(seedColorForAccent(AppAccentColor.violet), Colors.deepPurple);
    expect(seedColorForAccent(AppAccentColor.green), Colors.green);
  });
}
