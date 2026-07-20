import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/aethertune_app.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('starts, completes setup, imports a local entry, and queues it', (
    tester,
  ) async {
    final audio = _SmokePlaybackAudioEngine();
    await tester.pumpWidget(AetherTuneApp(audioEngine: audio));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to AetherTune'), findsOneWidget);
    await tester.tap(find.text('Skip setup'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Library'), findsWidgets);

    final homeContext = tester.element(find.byType(HomeScreen));
    final library = Provider.of<LibraryStore>(homeContext, listen: false);
    final player = Provider.of<PlayerController>(homeContext, listen: false);
    final track = Track(
      id: 'smoke-local-track',
      title: 'Morning Signal',
      artist: 'AetherTune Test Artist',
      album: 'Smoke Session',
      duration: const Duration(minutes: 3, seconds: 12),
      localPath: '/music/Morning Signal.mp3',
    );

    await library.addTracks(<Track>[track]);
    await tester.pumpAndSettle();
    expect(find.text('Morning Signal'), findsWidgets);

    await library.toggleFavorite(track.id);
    final customSmartPlaylist = await library.createCustomSmartPlaylist(
      name: 'Smoke favorites',
      favoritesOnly: true,
    );
    await tester.pumpAndSettle();
    final favoritesPlaylist = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'smart:favorites',
    );
    final customPlaylist = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'custom-smart:${customSmartPlaylist.id}',
    );
    final artistCollection = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'artist:aethertune test artist',
    );
    final albumCollection = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'album:smoke session',
    );
    final genreCollection = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'genre:unknown genre',
    );
    final sourceCollection = audio.browsePlaylists.singleWhere(
      (playlist) => playlist.id == 'source:local',
    );
    expect(favoritesPlaylist.tracks.map((item) => item.id), <String>[track.id]);
    expect(customPlaylist.tracks.map((item) => item.id), <String>[track.id]);
    expect(artistCollection.category, MediaLibraryBrowseCategory.artist);
    expect(albumCollection.category, MediaLibraryBrowseCategory.album);
    expect(genreCollection.category, MediaLibraryBrowseCategory.genre);
    expect(sourceCollection.category, MediaLibraryBrowseCategory.source);
    expect(artistCollection.tracks.map((item) => item.id), <String>[track.id]);
    expect(albumCollection.tracks.map((item) => item.id), <String>[track.id]);
    expect(genreCollection.tracks.map((item) => item.id), <String>[track.id]);
    expect(sourceCollection.tracks.map((item) => item.id), <String>[track.id]);
    Iterable<MediaLibraryBrowseFolder> allFolders(
      Iterable<MediaLibraryBrowseFolder> folders,
    ) sync* {
      for (final folder in folders) {
        yield folder;
        yield* allFolders(folder.children);
      }
    }

    final directTrackFolder = allFolders(audio.browseFolders).singleWhere(
      (folder) => folder.directTracks.any((item) => item.id == track.id),
    );
    expect(directTrackFolder.queueTracks.map((item) => item.id), <String>[
      track.id,
    ]);

    final playCallsBefore = audio.playCalls;
    await player.playTrack(track);
    await tester.pump();

    expect(player.current?.id, track.id);
    expect(audio.queue.map((item) => item.id), <String>[track.id]);
    expect(audio.playCalls, greaterThan(playCallsBefore));

    await library.updateTrackMetadata(
      track.id,
      title: 'Morning Signal (Edited)',
      artist: track.artist,
      album: track.album,
      genre: 'Electronic',
    );
    await tester.pumpAndSettle();

    expect(player.current?.title, 'Morning Signal (Edited)');
    expect(audio.queue.single.title, 'Morning Signal (Edited)');
  });
}

class _SmokePlaybackAudioEngine
    implements MediaLibraryBrowsePlaybackAudioEngine {
  List<Track> queue = const <Track>[];
  List<MediaLibraryBrowsePlaylist> browsePlaylists =
      const <MediaLibraryBrowsePlaylist>[];
  List<MediaLibraryBrowseFolder> browseFolders =
      const <MediaLibraryBrowseFolder>[];
  int playCalls = 0;

  @override
  Stream<Object?> get stateChanges => const Stream<Object?>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<ProcessingState> get processingStateStream =>
      const Stream<ProcessingState>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();

  @override
  bool get playing => playCalls > 0;

  @override
  bool get shuffleModeEnabled => false;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  @override
  double get volume => 1;

  @override
  bool get hasNext => false;

  @override
  bool get hasPrevious => false;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    queue = List<Track>.unmodifiable(tracks);
  }

  @override
  void setMediaLibraryBrowseTracks(
    Iterable<Track> tracks, {
    required MediaLibraryTrackSelectionHandler onTrackSelected,
    Iterable<MediaLibraryBrowsePlaylist> playlists =
        const <MediaLibraryBrowsePlaylist>[],
    Iterable<MediaLibraryBrowseFolder> folders =
        const <MediaLibraryBrowseFolder>[],
    MediaLibraryPlaylistTrackSelectionHandler? onPlaylistTrackSelected,
  }) {
    browsePlaylists = List<MediaLibraryBrowsePlaylist>.unmodifiable(playlists);
    browseFolders = List<MediaLibraryBrowseFolder>.unmodifiable(folders);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {}

  @override
  Future<void> seekToNext() async {}

  @override
  Future<void> seekToPrevious() async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
