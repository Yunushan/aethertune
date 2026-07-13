import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/library_sync_store.dart';
import '../data/local_folder_watch_store.dart';
import '../data/self_hosted_provider_store.dart';
import '../player/playback_audio_engine.dart';
import '../player/player_controller.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'theme_colors.dart';
import 'widgets/library_sync_automatic_upload.dart';
import 'widgets/offline_cache_foreground_worker.dart';

class AetherTuneApp extends StatefulWidget {
  const AetherTuneApp({super.key, this.audioEngine});

  final PlaybackAudioEngine? audioEngine;

  @override
  State<AetherTuneApp> createState() => _AetherTuneAppState();
}

class _AetherTuneAppState extends State<AetherTuneApp> {
  int _onboardingDestination = 0;

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
          create: (_) => PlayerController(audioEngine: widget.audioEngine)
            ..loadPersistedQueue()
            ..loadPersistedPlaybackSettings(),
          update: (_, library, selfHosted, player) {
            final controller = player ??
                (PlayerController(audioEngine: widget.audioEngine)
                  ..loadPersistedQueue()
                  ..loadPersistedPlaybackSettings());
            controller.setOfflineModeEnabled(library.offlineModeEnabled);
            controller.setTrackResolver(selfHosted.resolveTrack);
            return controller;
          },
        ),
      ],
      child: OfflineCacheForegroundWorker(
        child: LibrarySyncAutomaticUpload(
          child: Consumer2<LibraryStore, PlayerController>(
          builder: (context, library, player, _) {
            return MaterialApp(
              locale: localeForLanguagePreference(
                library.languagePreference,
              ),
              onGenerateTitle: (context) =>
                  AppLocalizations.of(context)!.appTitle,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              themeMode: _themeModeForPreference(library.themePreference),
              theme: _lightTheme(library.accentColor),
              darkTheme: _darkThemeForPreference(
                library.themePreference,
                library.accentColor,
              ),
              home: !library.loaded
                  ? const _AppLoadingScreen()
                  : CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                            () => unawaited(player.togglePlayPause()),
                        const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
                            () => unawaited(player.next()),
                        const SingleActivator(
                          LogicalKeyboardKey.mediaTrackPrevious,
                        ): () => unawaited(player.previous()),
                        const SingleActivator(
                          LogicalKeyboardKey.keyK,
                          control: true,
                        ): () => unawaited(player.togglePlayPause()),
                      },
                      child: Focus(
                        autofocus: true,
                        child: library.onboardingCompleted
                            ? HomeScreen(
                                initialTab: _onboardingDestination,
                                onRestartOnboarding: () => unawaited(
                                  library.setOnboardingCompleted(false),
                                ),
                              )
                            : OnboardingScreen(
                                onFinished: (destination) async {
                                  setState(() {
                                    _onboardingDestination = destination;
                                  });
                                  await library.setOnboardingCompleted(true);
                                },
                              ),
                      ),
                    ),
            );
          },
          ),
        ),
      ),
    );
  }
}

Locale? localeForLanguagePreference(AppLanguagePreference preference) {
  switch (preference) {
    case AppLanguagePreference.system:
      return null;
    case AppLanguagePreference.english:
      return const Locale('en');
    case AppLanguagePreference.turkish:
      return const Locale('tr');
    case AppLanguagePreference.arabic:
      return const Locale('ar');
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

class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          semanticsLabel: localizations.loading,
        ),
      ),
    );
  }
}
