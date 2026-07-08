import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/local_library_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  test('declares local-only searchable playback capabilities', () {
    const provider = LocalLibraryProvider();

    expect(provider.id, LocalLibraryProvider.providerId);
    expect(provider.name, 'Local Library');
    expect(
      provider.capabilities,
      <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.directPlayback,
      },
    );
    expect(provider.disclosure.isLocalOnly, isTrue);
    expect(provider.disclosure.usesNetwork, isFalse);
  });

  test('searches local library track metadata and paths', () async {
    final provider = LocalLibraryProvider(
      tracks: <Track>[
        Track(
          id: 'one',
          title: 'Sea Glass',
          artist: 'Mira',
          album: 'Blue Rooms',
          genre: 'Ambient',
          localPath: '/music/ambient/sea-glass.mp3',
        ),
        Track(
          id: 'two',
          title: 'Night Drive',
          artist: 'Yunus',
          album: 'Road Mix',
          genre: 'Electronic',
          streamUrl: 'https://stream.example.test/night.mp3',
          sourceId: 'internet-archive',
        ),
      ],
    );

    expect(
      (await provider.search('ambient')).map((track) => track.id),
      <String>['one'],
    );
    expect(
      (await provider.search('road')).map((track) => track.id),
      <String>['two'],
    );
    expect(
      (await provider.search('sea-glass')).map((track) => track.id),
      <String>['one'],
    );
  });

  test('can delegate search to the library store search surface', () async {
    final searchedQueries = <String>[];
    final provider = LocalLibraryProvider(
      searchTracks: (query) {
        searchedQueries.add(query);
        return <Track>[Track(id: 'match', title: 'Match')];
      },
    );

    final tracks = await provider.search('lyrics query');

    expect(searchedQueries, <String>['lyrics query']);
    expect(tracks.single.id, 'match');
  });

  test('resolves saved local file and stream tracks', () async {
    const provider = LocalLibraryProvider();

    final fileUri = await provider.resolveStream(
      Track(
        id: 'local',
        title: 'Local',
        localPath: '/music/local.mp3',
      ),
    );
    final streamUri = await provider.resolveStream(
      Track(
        id: 'stream',
        title: 'Stream',
        streamUrl: 'https://stream.example.test/audio.mp3',
      ),
    );

    expect(fileUri!.isScheme('file'), isTrue);
    expect(streamUri, Uri.parse('https://stream.example.test/audio.mp3'));
  });
}
