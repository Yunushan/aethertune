import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';

void main() {
  test('Track JSON round trip keeps core fields', () {
    final track = Track(
      id: '1',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      genre: 'Jazz',
      duration: const Duration(seconds: 42),
      localPath: '/music/song.mp3',
      sourceId: 'local',
      isFavorite: true,
      addedAt: DateTime.utc(2026),
    );

    final decoded = Track.fromJson(track.toJson());

    expect(decoded.id, track.id);
    expect(decoded.title, track.title);
    expect(decoded.artist, track.artist);
    expect(decoded.album, track.album);
    expect(decoded.genre, track.genre);
    expect(decoded.duration, track.duration);
    expect(decoded.localPath, track.localPath);
    expect(decoded.isFavorite, isTrue);
  });

  test('Track JSON falls back to unknown genre for older saved tracks', () {
    final decoded = Track.fromJson(<String, Object?>{
      'id': 'legacy',
      'title': 'Legacy Song',
    });

    expect(decoded.genre, 'Unknown Genre');
  });

  test('Stable local id is deterministic', () {
    final a = Track.stableLocalId('/tmp/audio.mp3');
    final b = Track.stableLocalId('/tmp/audio.mp3');
    expect(a, b);
  });
}
