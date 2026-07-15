import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/aethertune_app.dart';

void main() {
  test('uses compact density only for compact desktop preference', () {
    expect(
      visualDensityForDesktopPreference(
        DesktopDensityPreference.compact,
        TargetPlatform.windows,
      ),
      VisualDensity.compact,
    );
    expect(
      visualDensityForDesktopPreference(
        DesktopDensityPreference.compact,
        TargetPlatform.macOS,
      ),
      VisualDensity.compact,
    );
    expect(
      visualDensityForDesktopPreference(
        DesktopDensityPreference.compact,
        TargetPlatform.linux,
      ),
      VisualDensity.compact,
    );
  });

  test('keeps phone and tablet layouts at standard density', () {
    expect(
      visualDensityForDesktopPreference(
        DesktopDensityPreference.compact,
        TargetPlatform.android,
      ),
      VisualDensity.standard,
    );
    expect(
      visualDensityForDesktopPreference(
        DesktopDensityPreference.comfortable,
        TargetPlatform.windows,
      ),
      VisualDensity.standard,
    );
  });
}
