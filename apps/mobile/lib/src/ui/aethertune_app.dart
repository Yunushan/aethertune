import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/local_diagnostic_log.dart';
import '../data/library_sync_store.dart';
import '../data/listen_together_store.dart';
import '../data/local_folder_watch_store.dart';
import '../data/custom_catalog_store.dart';
import '../data/self_hosted_provider_store.dart';
import '../player/playback_audio_engine.dart';
import '../player/player_controller.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'theme_colors.dart';
import 'widgets/library_sync_automatic_upload.dart';
import 'widgets/listen_together_foreground_sync.dart';
import 'widgets/desktop_global_hotkeys.dart';
import 'widgets/offline_cache_foreground_worker.dart';
import 'widgets/podcast_rss_refresh_worker.dart';
import 'widgets/desktop_tray_controls.dart';
import 'widgets/aethertune_deep_link_listener.dart';
import 'widgets/android_screenshot_protection.dart';

class AetherTuneApp extends StatefulWidget {
  const AetherTuneApp({
    super.key,
    this.audioEngine,
    this.diagnostics,
    this.incomingUriStream,
  });

  final PlaybackAudioEngine? audioEngine;
  final LocalDiagnosticLog? diagnostics;
  final Stream<Uri>? incomingUriStream;

  @override
  State<AetherTuneApp> createState() => _AetherTuneAppState();
}

class _AetherTuneAppState extends State<AetherTuneApp> {
  int _onboardingDestination = 0;
  int _homeGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(
          create: (_) => LibraryStore()..load(),
        ),
        ChangeNotifierProvider<LocalDiagnosticLog>(
          create: (_) => widget.diagnostics ?? LocalDiagnosticLog()..load(),
        ),
        ChangeNotifierProvider<SelfHostedProviderStore>(
          create: (_) => SelfHostedProviderStore()..load(),
        ),
        ChangeNotifierProvider<CustomCatalogStore>(
          create: (_) => CustomCatalogStore()..load(),
        ),
        ChangeNotifierProvider<LibrarySyncStore>(
          create: (_) => LibrarySyncStore()..load(),
        ),
        ChangeNotifierProxyProvider<LibrarySyncStore, ListenTogetherStore>(
          create: (_) => ListenTogetherStore(),
          update: (_, sync, listenTogether) {
            final store = listenTogether ?? ListenTogetherStore();
            store.updateGatewayFactory(
              sync.isConfigured ? sync.createListenTogetherGateway : null,
            );
            return store;
          },
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
      child: PodcastRssRefreshWorker(
        child: AndroidScreenshotProtection(
        child: OfflineCacheForegroundWorker(
          child: LibrarySyncAutomaticUpload(
          child: ListenTogetherForegroundSync(
          child: DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) =>
                Consumer2<LibraryStore, PlayerController>(
              builder: (context, library, player, _) {
                return DesktopTrayControls(
                  onTogglePlayPause: player.togglePlayPause,
                  onPrevious: player.previous,
                  onNext: player.next,
                  minimizeToTray: library.desktopMinimizeToTray,
                  child: DesktopGlobalHotkeys(
                    onTogglePlayPause: player.togglePlayPause,
                    onPrevious: player.previous,
                    onNext: player.next,
                    child: MaterialApp(
                    scaffoldMessengerKey: _scaffoldMessengerKey,
                    locale: localeForLanguagePreference(
                      library.languagePreference,
                    ),
                    onGenerateTitle: (context) =>
                        AppLocalizations.of(context)!.appTitle,
                    debugShowCheckedModeBanner: false,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    themeMode: _themeModeForPreference(library.themePreference),
                    theme: _lightTheme(
                      library.accentColor,
                      dynamicColorScheme: lightDynamic,
                      visualDensity: visualDensityForDesktopPreference(
                        library.desktopDensityPreference,
                        defaultTargetPlatform,
                      ),
                    ),
                    darkTheme: _darkThemeForPreference(
                      library.themePreference,
                      library.accentColor,
                      dynamicColorScheme: darkDynamic,
                      visualDensity: visualDensityForDesktopPreference(
                        library.desktopDensityPreference,
                        defaultTargetPlatform,
                      ),
                    ),
                    builder: (context, child) => AetherTuneDeepLinkListener(
                      library: library,
                      incomingUriStream: widget.incomingUriStream,
                      onImported: (_) => _openPlaylistsFromDeepLink(),
                      child: child ?? const SizedBox.shrink(),
                    ),
                    home: !library.loaded
                        ? const _AppLoadingScreen()
                        : CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.mediaPlayPause,
                              ): () => unawaited(player.togglePlayPause()),
                              const SingleActivator(
                                LogicalKeyboardKey.mediaTrackNext,
                              ): () => unawaited(player.next()),
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
                                      key: ValueKey<String>(
                                        'home-$_homeGeneration',
                                      ),
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
                                        await library.setOnboardingCompleted(
                                          true,
                                        );
                                      },
                                    ),
                            ),
                          ),
                    ),
                  ),
                );
              },
            ),
            ),
          ),
          ),
        ),
        ),
      ),
    );
  }

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void _openPlaylistsFromDeepLink() {
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingDestination = 2;
      _homeGeneration += 1;
    });
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

ThemeData _lightTheme(
  AppAccentColor accentColor, {
  ColorScheme? dynamicColorScheme,
  VisualDensity visualDensity = VisualDensity.standard,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: lightColorSchemeForAccent(
      accentColor,
      dynamicColorScheme: dynamicColorScheme,
    ),
    brightness: Brightness.light,
    visualDensity: visualDensity,
  );
}

ThemeData _darkThemeForPreference(
  AppThemePreference preference,
  AppAccentColor accentColor, {
  ColorScheme? dynamicColorScheme,
  VisualDensity visualDensity = VisualDensity.standard,
}) {
  final colorScheme = darkColorSchemeForAccent(
    accentColor,
    dynamicColorScheme: dynamicColorScheme,
  );
  if (preference == AppThemePreference.amoled) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.black,
      ),
      visualDensity: visualDensity,
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: Brightness.dark,
    visualDensity: visualDensity,
  );
}

VisualDensity visualDensityForDesktopPreference(
  DesktopDensityPreference preference,
  TargetPlatform platform,
) {
  final isDesktop =
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
  if (!isDesktop || preference == DesktopDensityPreference.comfortable) {
    return VisualDensity.standard;
  }
  return VisualDensity.compact;
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
