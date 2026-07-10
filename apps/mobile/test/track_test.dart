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
      contentHash: 'fnv64-0011223344556677',
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
    expect(decoded.contentHash, track.contentHash);
    expect(decoded.isFavorite, isTrue);
  });

  test('Track JSON falls back to unknown genre for older saved tracks', () {
    final decoded = Track.fromJson(<String, Object?>{
      'id': 'legacy',
      'title': 'Legacy Song',
    });

    expect(decoded.genre, 'Unknown Genre');
  });

  test('Track JSON round trip keeps provider stream fields', () {
    final track = Track(
      id: 'radio-1',
      title: 'Aether Radio',
      artist: 'Radio Browser',
      album: 'Internet Radio',
      genre: 'Jazz',
      artworkUri: Uri.parse('https://station.example.test/icon.png'),
      providerArtworkId: 'station-art-1',
      providerArtworkVersion: 'etag-1',
      streamUrl: 'https://stream.example.test/aac',
      sourceId: 'radio-browser',
      externalId: 'station-1',
    );

    final decoded = Track.fromJson(track.toJson());

    expect(decoded.streamUrl, 'https://stream.example.test/aac');
    expect(decoded.sourceId, 'radio-browser');
    expect(decoded.externalId, 'station-1');
    expect(decoded.providerArtworkId, 'station-art-1');
    expect(decoded.providerArtworkVersion, 'etag-1');
    expect(
      decoded.artworkUri,
      Uri.parse('https://station.example.test/icon.png'),
    );
    expect(decoded.isPlayable, isTrue);
  });

  test('ephemeral authenticated streams are never serialized', () {
    final track = Track(
      id: 'private',
      title: 'Private stream',
      streamUrl: 'https://media.example.test/stream?api_key=secret',
      streamUrlIsEphemeral: true,
      sourceId: 'self-hosted-jellyfin-account',
      externalId: 'song-1',
    );

    final json = track.toJson();
    final restored = Track.fromJson(json);

    expect(track.isPlayable, isTrue);
    expect(json['streamUrl'], isNull);
    expect(json.toString(), isNot(contains('secret')));
    expect(restored.streamUrl, isNull);
    expect(restored.isPlayable, isFalse);
  });

  test('ephemeral provider artwork paths are never serialized', () {
    final track = Track(
      id: 'private-artwork',
      title: 'Private artwork',
      artworkUri: Uri.file('/private/cache/provider-artwork.png'),
      artworkUriIsEphemeral: true,
      providerArtworkId: 'cover-1',
      providerArtworkVersion: 'v1',
      sourceId: 'self-hosted-jellyfin-account',
    );

    final json = track.toJson();
    final restored = Track.fromJson(json);

    expect(json['artworkUri'], isNull);
    expect(json.toString(), isNot(contains('/private/cache')));
    expect(restored.artworkUri, isNull);
    expect(restored.artworkUriIsEphemeral, isFalse);
    expect(restored.providerArtworkId, 'cover-1');
    expect(restored.providerArtworkVersion, 'v1');
  });

  test('playable source checks ignore blank paths and URLs', () {
    final blankLocal = Track(
      id: 'blank-local',
      title: 'Blank Local',
      localPath: '  ',
    );
    final blankStream = Track(
      id: 'blank-stream',
      title: 'Blank Stream',
      streamUrl: '',
    );
    final localTrack = Track(
      id: 'local',
      title: 'Local',
      localPath: '/music/local.mp3',
    );
    final streamTrack = Track(
      id: 'stream',
      title: 'Stream',
      streamUrl: 'https://media.example.test/song.mp3',
    );

    expect(blankLocal.hasLocalSource, isFalse);
    expect(blankLocal.isPlayable, isFalse);
    expect(blankStream.hasStreamSource, isFalse);
    expect(blankStream.isPlayable, isFalse);
    expect(localTrack.hasLocalSource, isTrue);
    expect(localTrack.isPlayable, isTrue);
    expect(streamTrack.hasStreamSource, isTrue);
    expect(streamTrack.isPlayable, isTrue);
  });

  test('Stable local id is deterministic', () {
    final a = Track.stableLocalId('/tmp/audio.mp3');
    final b = Track.stableLocalId('/tmp/audio.mp3');
    expect(a, b);
  });
}
