import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/lyrics_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/lyrics_search_sheet.dart';

void main() {
  testWidgets('shows disclosure and returns an attributed lyrics result', (
    tester,
  ) async {
    final provider = _FakeLyricsProvider();
    await tester.pumpWidget(_LyricsSearchHarness(provider: provider));

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();

    expect(find.text('Search Test Lyrics'), findsOneWidget);
    expect(find.textContaining('lyrics.example.test'), findsOneWidget);
    expect(find.textContaining('stored locally with attribution'), findsOneWidget);
    expect(provider.lastQuery!.keywords, 'Signal Mira Dawn');
    expect(find.text('Signal'), findsOneWidget);
    expect(find.text('Instrumental Cut'), findsOneWidget);

    final instrumental = tester.widget<ListTile>(
      find.byKey(const Key('lyrics-result-instrumental')),
    );
    expect(instrumental.enabled, isFalse);

    await tester.tap(find.byKey(const Key('lyrics-result-synced')));
    await tester.pumpAndSettle();

    expect(find.text('Selected: synced'), findsOneWidget);
  });

  testWidgets('shows a retryable provider error', (tester) async {
    final provider = _FakeLyricsProvider(failuresRemaining: 1);
    await tester.pumpWidget(_LyricsSearchHarness(provider: provider));

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();

    expect(find.text('Lyrics search failed'), findsOneWidget);
    expect(find.textContaining('temporary failure'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lyrics-result-synced')), findsOneWidget);
    expect(provider.searchCalls, 2);
  });

  testWidgets('shows loading and empty result states', (tester) async {
    final provider = _ControlledLyricsProvider();
    await tester.pumpWidget(_LyricsSearchHarness(provider: provider));

    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('lyrics-search-loading')), findsOneWidget);

    provider.complete(const <LyricsSearchResult>[]);
    await tester.pumpAndSettle();

    expect(find.text('No lyrics found'), findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);
  });
}

class _LyricsSearchHarness extends StatefulWidget {
  const _LyricsSearchHarness({required this.provider});

  final LyricsProvider provider;

  @override
  State<_LyricsSearchHarness> createState() => _LyricsSearchHarnessState();
}

class _LyricsSearchHarnessState extends State<_LyricsSearchHarness> {
  LyricsSearchResult? _selected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Column(
              children: <Widget>[
                TextButton(
                  onPressed: () async {
                    final selected = await showLyricsSearchSheet(
                      context,
                      track: _track,
                      provider: widget.provider,
                    );
                    if (mounted) {
                      setState(() => _selected = selected);
                    }
                  },
                  child: const Text('Open search'),
                ),
                Text('Selected: ${_selected?.externalId ?? 'none'}'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FakeLyricsProvider implements LyricsProvider {
  _FakeLyricsProvider({this.failuresRemaining = 0});

  int failuresRemaining;
  int searchCalls = 0;
  LyricsSearchQuery? lastQuery;

  @override
  String get id => 'test-lyrics';

  @override
  String get name => 'Test Lyrics';

  @override
  String get description => 'Test lyrics provider.';

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
        networkDomains: <String>['lyrics.example.test'],
        dataSent: <String>['track search terms'],
        cachesMetadata: true,
      );

  @override
  Future<List<LyricsSearchResult>> search(LyricsSearchQuery query) async {
    searchCalls += 1;
    lastQuery = query;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const FormatException('temporary failure');
    }
    return <LyricsSearchResult>[_syncedResult, _instrumentalResult];
  }
}

class _ControlledLyricsProvider implements LyricsProvider {
  final _completer = Completer<List<LyricsSearchResult>>();

  void complete(List<LyricsSearchResult> results) {
    _completer.complete(results);
  }

  @override
  String get id => 'controlled-lyrics';

  @override
  String get name => 'Controlled Lyrics';

  @override
  String get description => 'Controlled test provider.';

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
        networkDomains: <String>['lyrics.example.test'],
        dataSent: <String>['track search terms'],
      );

  @override
  Future<List<LyricsSearchResult>> search(LyricsSearchQuery query) {
    return _completer.future;
  }
}

final _track = Track(
  id: 'track',
  title: 'Signal',
  artist: 'Mira',
  album: 'Dawn',
  duration: Duration(minutes: 3),
  localPath: '/music/signal.mp3',
);

final _syncedResult = LyricsSearchResult(
  providerId: 'test-lyrics',
  providerName: 'Test Lyrics',
  externalId: 'synced',
  trackName: 'Signal',
  artistName: 'Mira',
  albumName: 'Dawn',
  duration: const Duration(minutes: 3),
  instrumental: false,
  plainLyrics: 'First line',
  syncedLyrics: '[00:01.00]First line',
  sourceUri: Uri.parse('https://lyrics.example.test/api/get/synced'),
);

final _instrumentalResult = LyricsSearchResult(
  providerId: 'test-lyrics',
  providerName: 'Test Lyrics',
  externalId: 'instrumental',
  trackName: 'Instrumental Cut',
  artistName: 'Mira',
  albumName: 'Dawn',
  duration: const Duration(minutes: 3),
  instrumental: true,
  plainLyrics: '',
  syncedLyrics: '',
  sourceUri: Uri.parse('https://lyrics.example.test/api/get/instrumental'),
);
