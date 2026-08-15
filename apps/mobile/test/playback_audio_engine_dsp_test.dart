import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android pipeline accepts audio effect settings before a source loads',
    () async {
      final engine = JustAudioPlaybackEngine(enableAndroidAudioEffects: true);
      addTearDown(engine.dispose);

      expect(engine.supportsEqualizer, isTrue);
      expect(engine.supportsLoudnessEnhancer, isTrue);
      await engine.setEqualizerProfile(
        const PlaybackEqualizerProfile(
          preset: PlaybackEqualizerPreset.bassBoost,
        ),
      );
      await engine.setEqualizerEnabled(true);
      await engine.setLoudnessEnhancerTargetGain(4);
      await engine.setLoudnessEnhancerEnabled(true);
      expect(await engine.loadEqualizerBands(), isEmpty);
    },
  );

  test(
    'default pipeline reports platform audio effects as unavailable',
    () async {
      final engine = JustAudioPlaybackEngine();
      addTearDown(engine.dispose);

      expect(engine.supportsEqualizer, isFalse);
      expect(engine.supportsLoudnessEnhancer, isFalse);
    },
  );

  test('browse models keep library collections immutable', () {
    final track = Track(id: 'track-1', title: 'Track 1');
    final playlist = MediaLibraryBrowsePlaylist(
      id: 'playlist-1',
      title: 'Playlist 1',
      tracks: <Track>[track],
      artworkUri: Uri.parse('https://example.test/artwork.jpg'),
      category: MediaLibraryBrowseCategory.artist,
    );
    final childFolder = MediaLibraryBrowseFolder(
      id: 'child-folder',
      title: 'Child Folder',
      queueTracks: const <Track>[],
    );
    final folder = MediaLibraryBrowseFolder(
      id: 'folder-1',
      title: 'Folder 1',
      queueTracks: <Track>[track],
      directTracks: <Track>[track],
      children: <MediaLibraryBrowseFolder>[childFolder],
    );

    expect(playlist.tracks, <Track>[track]);
    expect(playlist.category, MediaLibraryBrowseCategory.artist);
    expect(playlist.artworkUri, Uri.parse('https://example.test/artwork.jpg'));
    expect(() => playlist.tracks.add(track), throwsUnsupportedError);
    expect(folder.queueTracks, <Track>[track]);
    expect(folder.directTracks, <Track>[track]);
    expect(folder.children, hasLength(1));
    expect(() => folder.queueTracks.add(track), throwsUnsupportedError);
  });

  test('engine rejects invalid and metadata-only queues', () async {
    final engine = JustAudioPlaybackEngine();
    addTearDown(engine.dispose);

    await expectLater(
      engine.setQueue(const <Track>[], initialIndex: 0),
      throwsArgumentError,
    );
    await expectLater(
      engine.setQueue(<Track>[
        Track(id: 'track-1', title: 'Track 1'),
      ], initialIndex: 1),
      throwsA(isA<RangeError>()),
    );
    await expectLater(
      engine.setQueue(<Track>[
        Track(id: 'metadata', title: 'Metadata'),
      ], initialIndex: 0),
      throwsStateError,
    );
  });

  test(
    'default engine exposes capabilities and fails unsupported controls',
    () async {
      final engine = JustAudioPlaybackEngine();
      addTearDown(engine.dispose);

      expect(engine.supportsCrossfade, isTrue);
      expect(engine.crossfadeDuration, Duration.zero);
      expect(engine.supportsPitch, isFalse);
      expect(engine.supportsVirtualizer, isFalse);
      expect(engine.supportsSkipSilence, isFalse);
      expect(engine.supportsVisualizer, isFalse);
      expect(await engine.startVisualizer(), isFalse);
      await engine.stopVisualizer();

      expect(
        () => engine.setEqualizerProfile(
          const PlaybackEqualizerProfile(preset: PlaybackEqualizerPreset.flat),
        ),
        throwsUnsupportedError,
      );
      await expectLater(engine.setPitch(1.1), throwsUnsupportedError);
      await expectLater(
        engine.setEqualizerEnabled(true),
        throwsUnsupportedError,
      );
      await expectLater(engine.loadEqualizerBands(), throwsUnsupportedError);
      await expectLater(
        engine.setLoudnessEnhancerEnabled(true),
        throwsUnsupportedError,
      );
      await expectLater(
        engine.setLoudnessEnhancerTargetGain(3),
        throwsUnsupportedError,
      );
      await expectLater(
        engine.setVirtualizerEnabled(true),
        throwsUnsupportedError,
      );
      await expectLater(
        engine.setVirtualizerStrength(50),
        throwsUnsupportedError,
      );
      await expectLater(
        engine.setSkipSilenceEnabled(true),
        throwsUnsupportedError,
      );
      await expectLater(
        engine.setCrossfadeDuration(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    },
  );
}
