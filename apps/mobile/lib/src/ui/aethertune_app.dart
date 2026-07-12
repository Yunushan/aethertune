import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/library_sync_store.dart';
import '../data/local_folder_watch_store.dart';
import '../data/self_hosted_provider_store.dart';
import '../player/playback_audio_engine.dart';
import '../player/player_controller.dart';
import 'home_screen.dart';
import 'theme_colors.dart';

class AetherTuneApp extends StatelessWidget {
  const AetherTuneApp({super.key, this.audioEngine});

  final PlaybackAudioEngine? audioEngine;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(
          create: (_) => LibraryStore()..load(),
        ),
        ChangeNotifierProvider<SelfHostedProviderStore>(
          create: (_) => SelfHostedProviderStore()..load(),
        ),
        ChangeNotifierProvider<LibrarySyncStore>(
          create: (_) => LibrarySyncStore()..load(),
        ),
        ChangeNotifierProxyProvider<LibraryStore, LocalFolderWatchStore>(
          create: (_) => LocalFolderWatchStore(),
          update: (_, library, watcher) {
            final store = watcher ?? LocalFolderWatchStore();
            store.updateLibrary(library);
            return store;
          },
        ),
        ChangeNotifierProxyProvider2<
            LibraryStore,
            SelfHostedProviderStore,
            PlayerController>(
          create: (_) => PlayerController(audioEngine: audioEngine)
            ..loadPersistedQueue()
            ..loadPersistedPlaybackSettings(),
          update: (_, library, selfHosted, player) {
            final controller = player ??
                (PlayerController(audioEngine: audioEngine)
                  ..loadPersistedQueue()
                  ..loadPersistedPlaybackSettings());
            controller.setOfflineModeEnabled(library.offlineModeEnabled);
            controller.setTrackResolver(selfHosted.resolveTrack);
            return controller;
          },
        ),
      ],
      child: Consumer<LibraryStore>(
        builder: (context, library, _) {
          return MaterialApp(
            title: 'AetherTune',
            debugShowCheckedModeBanner: false,
            themeMode: _themeModeForPreference(library.themePreference),
            theme: _lightTheme(library.accentColor),
            darkTheme: _darkThemeForPreference(
              library.themePreference,
              library.accentColor,
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

ThemeMode _themeModeForPreference(AppThemePreference preference) {
  switch (preference) {
    case AppThemePreference.system:
      return ThemeMode.system;
    case AppThemePreference.light:
      return ThemeMode.light;
    case AppThemePreference.dark:
    case AppThemePreference.amoled:
      return ThemeMode.dark;
  }
}

ThemeData _lightTheme(AppAccentColor accentColor) {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seedColorForAccent(accentColor),
    brightness: Brightness.light,
  );
}

ThemeData _darkThemeForPreference(
  AppThemePreference preference,
  AppAccentColor accentColor,
) {
  final seedColor = seedColorForAccent(accentColor);
  if (preference == AppThemePreference.amoled) {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: seedColor,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.black,
      ),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seedColor,
    brightness: Brightness.dark,
  );
}
