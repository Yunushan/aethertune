import 'package:aethertune/src/domain/video_track_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters pseudo track IDs from embedded-track choices', () {
    expect(isSelectableEmbeddedVideoTrackId('auto'), isFalse);
    expect(isSelectableEmbeddedVideoTrackId(' NO '), isFalse);
    expect(isSelectableEmbeddedVideoTrackId('4'), isTrue);
  });

  test('prefers descriptive title and language in track labels', () {
    expect(
      videoTrackSelectionLabel(
        fallback: 'Audio',
        index: 0,
        title: 'Stereo',
        language: 'en',
      ),
      'Stereo (en)',
    );
    expect(
      videoTrackSelectionLabel(fallback: 'Caption', index: 1),
      'Caption 2',
    );
  });
}
