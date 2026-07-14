import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/artwork_crop.dart';
import 'package:aethertune/src/ui/widgets/artwork_crop_editor.dart';

void main() {
  testWidgets('edits and returns a panned, zoomed crop profile', (tester) async {
    ArtworkCrop? savedCrop;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                savedCrop = await showArtworkCropEditor(
                  context,
                  artworkUri: Uri.parse(
                    'data:image/png;base64,'
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
                    'CklEQVR4nGMAAQAABQABDQotxAAAAABJRU5ErkJggg==',
                  ),
                  initialCrop: ArtworkCrop.centered,
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('artwork-crop-preview')),
      const Offset(60, -30),
    );
    final sliderRect = tester.getRect(
      find.byKey(const Key('artwork-crop-zoom')),
    );
    await tester.tapAt(Offset(sliderRect.right - 4, sliderRect.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedCrop, isNotNull);
    expect(savedCrop!.alignmentX, greaterThan(0));
    expect(savedCrop!.alignmentY, lessThan(0));
    expect(savedCrop!.zoom, greaterThan(1));
  });
}
