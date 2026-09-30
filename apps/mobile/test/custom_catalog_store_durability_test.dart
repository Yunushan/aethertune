import 'dart:async';
import 'dart:convert';

import 'package:aethertune/src/data/custom_catalog_store.dart';
import 'package:aethertune/src/domain/custom_catalog_definition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _storageKey = 'aethertune.custom_catalogs.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('rejected writes leave memory and durable catalogs unchanged', () async {
    final backend = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final store = CustomCatalogStore();
    await store.save(_definition('catalog-first'));

    backend.rejectWrites = true;
    await expectLater(
      store.save(_definition('catalog-second')),
      throwsStateError,
    );
    expect(_ids(store), <String>['catalog-first']);
    await expectLater(store.remove('catalog-first'), throwsStateError);
    expect(_ids(store), <String>['catalog-first']);

    final restored = CustomCatalogStore();
    await restored.load();
    expect(_ids(restored), <String>['catalog-first']);
    expect(_persistedIds(), completion(<String>['catalog-first']));

    backend.rejectWrites = false;
    await store.save(_definition('catalog-second'));
    expect(
      _persistedIds(),
      completion(<String>['catalog-first', 'catalog-second']),
    );
  });

  test(
    'overlapping writes cannot replace a later acknowledged catalog',
    () async {
      final backend = _ControlledPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final store = CustomCatalogStore();
      await store.load();

      backend.pauseNextWrite();
      final first = store.save(_definition('catalog-first'));
      await backend.writeStarted;
      final second = store.save(_definition('catalog-second'));
      backend.resumeWrite();
      await Future.wait(<Future<void>>[first, second]);

      expect(_ids(store), <String>['catalog-first', 'catalog-second']);
      expect(
        _persistedIds(),
        completion(<String>['catalog-first', 'catalog-second']),
      );
    },
  );

  test('a damaged catalog document cannot be overwritten by an edit', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _storageKey: '{damaged',
    });
    final store = CustomCatalogStore();
    await expectLater(
      store.save(_definition('catalog-first')),
      throwsStateError,
    );
    expect(store.loadError, isNotNull);
    expect(store.definitions, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_storageKey),
      '{damaged',
    );
  });
}

CustomCatalogDefinition _definition(String id) =>
    CustomCatalogDefinition.create(
      id: id,
      name: id,
      catalogUrl: 'https://catalog.example.test/music.json',
      mediaDomains: const <String>[],
      allowInsecureHttp: false,
    );

List<String> _ids(CustomCatalogStore store) =>
    store.definitions.map((definition) => definition.id).toList();

Future<List<String>> _persistedIds() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final decoded =
      jsonDecode(preferences.getString(_storageKey)!) as List<dynamic>;
  return decoded
      .map((item) => (item as Map<String, dynamic>)['id'] as String)
      .toList();
}

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();

  bool rejectWrites = false;
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
