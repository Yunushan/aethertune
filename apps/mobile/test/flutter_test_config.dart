import 'dart:async';

import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/player/player_state_store.dart';

import 'support/library_storage_fixture.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Widget tests use fake async and cannot await native filesystem work.
  // FileLibraryStorage is exercised directly by its separate durability tests.
  libraryStorageFactory = PreferencesLibraryStorageFixture.new;
  playerStorageFactory = () =>
      PreferencesLibraryStorageFixture(key: 'aethertune.test.player.snapshot');
  await testMain();
}
