import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/android_playback_widget_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes only local artwork paths to the Android playback widget', () {
    final localTrack = Track(
      id: 'local',
      title: 'Local',
      artworkUri: Uri.file('/private/cache/local-cover.png'),
    );
    final remoteTrack = Track(
      id: 'remote',
      title: 'Remote',
      artworkUri: Uri.parse(
        'https://media.example.test/cover.png?credential=private-token',
      ),
    );
    final embeddedTrack = Track(
      id: 'embedded',
      title: 'Embedded',
      artworkUri: Uri.parse('data:image/png;base64,AA=='),
    );

    expect(
      localArtworkPathForWidget(localTrack),
      '/private/cache/local-cover.png',
    );
    expect(localArtworkPathForWidget(remoteTrack), isNull);
    expect(localArtworkPathForWidget(embeddedTrack), isNull);
    expect(localArtworkPathForWidget(null), isNull);
  });
}
