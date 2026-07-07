import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/offline_playback_policy.dart';

void main() {
  test('offline mode allows local tracks and blocks stream-only tracks', () {
    final localTrack = Track(
      id: 'local',
      title: 'Local Track',
      localPath: '/music/local.mp3',
    );
    final streamTrack = Track(
      id: 'stream',
      title: 'Stream Track',
      streamUrl: 'https://media.example.test/song.mp3',
      sourceId: 'archive',
    );

    expect(
      offlineModeAllowsPlayback(localTrack, offlineModeEnabled: true),
      isTrue,
    );
    expect(
      offlineModeAllowsPlayback(streamTrack, offlineModeEnabled: true),
      isFalse,
    );
    expect(
      offlineModeAllowsPlayback(streamTrack, offlineModeEnabled: false),
      isTrue,
    );
    expect(
      () => requireOfflineModePlaybackAllowed(
        streamTrack,
        offlineModeEnabled: true,
      ),
      throwsA(isA<OfflinePlaybackBlockedException>()),
    );
  });

  test('offline block messages name the blocked track', () {
    final track = Track(
      id: 'stream',
      title: 'Stream Track',
      streamUrl: 'https://media.example.test/song.mp3',
    );

    expect(
      offlinePlaybackBlockedMessage(track),
      'Offline mode is on. Stream Track needs a network stream.',
    );
  });
}
