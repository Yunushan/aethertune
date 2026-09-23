import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists normalized public channel follows on this device', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.youtube_channel_follows.v1': '''
        [
          {"id":"channel-2","title":"Orbit","thumbnailUri":"http://unsafe.example/image.jpg"},
          {"id":"channel-1","title":"Aether Radio","description":"Sessions","thumbnailUri":"https://i.ytimg.com/channel-1.jpg"},
          {"id":"channel-1","title":"Duplicate"},
          {"id":"","title":"Invalid"}
        ]
      ''',
    });
    final store = YouTubeChannelFollowStore();
    await store.load();
    addTearDown(store.dispose);

    expect(store.follows.map((follow) => follow.id), <String>[
      'channel-1',
      'channel-2',
    ]);
    expect(
      store.follows.first.thumbnailUri,
      Uri.parse('https://i.ytimg.com/channel-1.jpg'),
    );
    expect(store.follows.last.thumbnailUri, isNull);
    expect(store.isFollowed('channel-1'), isTrue);
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-3', title: 'Mira'),
        true,
      ),
      isTrue,
    );
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-3', title: 'Mira'),
        true,
      ),
      isFalse,
    );
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-1', title: 'Aether Radio'),
        false,
      ),
      isTrue,
    );

    final restored = YouTubeChannelFollowStore();
    await restored.load();
    addTearDown(restored.dispose);
    expect(restored.follows.map((follow) => follow.id), <String>[
      'channel-3',
      'channel-2',
    ]);
  });

  test(
    'exports and imports bounded public follows without account data',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = YouTubeChannelFollowStore();
      await store.load();
      addTearDown(store.dispose);
      await store.setFollowed(
        const YouTubeDataChannel(id: 'existing', title: 'Existing channel'),
        true,
      );

      final changed = await store.importFollowDocument(
        jsonEncode(<String, Object?>{
          'version': 1,
          'follows': <Object?>[
            <String, Object?>{
              'id': 'existing',
              'title': 'Updated channel',
              'description': 'Public metadata',
            },
            <String, Object?>{
              'id': 'new-channel',
              'title': 'New channel',
              'thumbnailUri': 'https://i.ytimg.com/new.jpg',
            },
          ],
        }),
      );

      expect(changed, 2);
      expect(store.follows.map((follow) => follow.id), <String>[
        'new-channel',
        'existing',
      ]);
      expect(store.follows.last.title, 'Updated channel');
      final exported =
          jsonDecode(store.exportFollowDocument()) as Map<String, Object?>;
      expect(exported['version'], 1);
      expect(exported['follows'], hasLength(2));
      expect(jsonEncode(exported), isNot(contains('credential')));
      expect(jsonEncode(exported), isNot(contains('playback')));

      final replaced = await store.importFollowDocument(
        jsonEncode(<String, Object?>{
          'version': 1,
          'follows': <Object?>[
            <String, Object?>{'id': 'only-channel', 'title': 'Only channel'},
          ],
        }),
        replace: true,
      );
      expect(replaced, 3);
      expect(store.follows.map((follow) => follow.id), <String>[
        'only-channel',
      ]);

      await expectLater(
        store.importFollowDocument('{"version":2,"follows":[]}'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        store.importFollowDocument('{"version":1,"follows":[{}]}'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('follows account channels in one device-local update', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = YouTubeChannelFollowStore();
    await store.load();
    addTearDown(store.dispose);

    expect(
      await store.followAll(const <YouTubeDataChannel>[
        YouTubeDataChannel(id: 'channel-2', title: 'Orbit'),
        YouTubeDataChannel(id: 'channel-1', title: 'Aether'),
        YouTubeDataChannel(id: 'channel-1', title: 'Aether'),
        YouTubeDataChannel(id: '', title: 'Ignored'),
      ]),
      2,
    );
    expect(store.follows.map((follow) => follow.id), <String>[
      'channel-1',
      'channel-2',
    ]);
    expect(await store.followAll(const <YouTubeDataChannel>[]), 0);
  });

  test('rejected and thrown writes preserve acknowledged follows', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final store = YouTubeChannelFollowStore();
    addTearDown(store.dispose);
    const first = YouTubeDataChannel(id: 'first', title: 'First');
    const second = YouTubeDataChannel(id: 'second', title: 'Second');
    await store.setFollowed(first, true);

    backend.rejectWrites = true;
    await expectLater(store.setFollowed(second, true), throwsStateError);
    await expectLater(store.setFollowed(first, false), throwsStateError);
    await expectLater(
      store.followAll(const <YouTubeDataChannel>[second]),
      throwsStateError,
    );
    await expectLater(
      store.importFollowDocument(
        '{"version":1,"follows":[{"id":"second","title":"Second"}]}',
      ),
      throwsStateError,
    );
    expect(store.follows.map((follow) => follow.id), <String>['first']);

    backend.rejectWrites = false;
    backend.throwWrites = true;
    await expectLater(store.setFollowed(second, true), throwsStateError);
    expect(store.follows.map((follow) => follow.id), <String>['first']);

    final restored = YouTubeChannelFollowStore();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.follows.map((follow) => follow.id), <String>['first']);
    expect(await _persistedIds(), <String>['first']);

    backend.throwWrites = false;
    await store.setFollowed(second, true);
    expect(await _persistedIds(), <String>['first', 'second']);
  });

  test('overlapping follow writes serialize against durable state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final backend = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final store = YouTubeChannelFollowStore();
    addTearDown(store.dispose);
    await store.load();

    backend.pauseNextWrite();
    final first = store.setFollowed(
      const YouTubeDataChannel(id: 'first', title: 'First'),
      true,
    );
    await backend.writeStarted;
    final second = store.followAll(const <YouTubeDataChannel>[
      YouTubeDataChannel(id: 'second', title: 'Second'),
    ]);
    backend.resumeWrite();
    expect(await first, isTrue);
    expect(await second, 1);
    expect(store.follows.map((follow) => follow.id), <String>[
      'first',
      'second',
    ]);
    expect(await _persistedIds(), <String>['first', 'second']);
  });

  test('corrupt follow storage cannot be overwritten by an edit', () async {
    const key = 'aethertune.youtube_channel_follows.v1';
    SharedPreferences.setMockInitialValues(<String, Object>{key: '{damaged'});
    final store = YouTubeChannelFollowStore();
    addTearDown(store.dispose);
    await expectLater(
      store.setFollowed(
        const YouTubeDataChannel(id: 'first', title: 'First'),
        true,
      ),
      throwsStateError,
    );
    expect(store.loadError, isNotNull);
    expect(store.follows, isEmpty);
    expect(store.exportFollowDocument, throwsStateError);
    expect((await SharedPreferences.getInstance()).getString(key), '{damaged');
  });

  test('export requires a completed load', () {
    final store = YouTubeChannelFollowStore();
    addTearDown(store.dispose);
    expect(store.exportFollowDocument, throwsStateError);
  });
}

Future<List<String>> _persistedIds() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final decoded =
      jsonDecode(
            preferences.getString('aethertune.youtube_channel_follows.v1')!,
          )
          as List<dynamic>;
  return decoded
      .map((item) => (item as Map<String, dynamic>)['id'] as String)
      .toList();
}

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  bool rejectWrites = false;
  bool throwWrites = false;
  Completer<void>? _pausedWrite;
  Completer<void>? _activeWrite;
  Completer<void>? _writeStarted;

  Future<void> get writeStarted => _writeStarted!.future;

  void pauseNextWrite() {
    _pausedWrite = Completer<void>();
    _writeStarted = Completer<void>();
  }

  void resumeWrite() => _activeWrite?.complete();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectWrites) {
      return false;
    }
    if (throwWrites) {
      throw StateError('Platform write failed.');
    }
    final pause = _pausedWrite;
    if (pause != null) {
      _pausedWrite = null;
      _activeWrite = pause;
      _writeStarted?.complete();
      await pause.future;
      _activeWrite = null;
    }
    return super.setValue(valueType, key, value);
  }
}
