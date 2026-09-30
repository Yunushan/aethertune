part of 'home_screen.dart';

class _AccentColorDropdownLabel extends StatelessWidget {
  const _AccentColorDropdownLabel({required this.accentColor});

  final AppAccentColor accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: usesSystemAccent(accentColor)
                ? Theme.of(context).colorScheme.primary
                : seedColorForAccent(accentColor),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: const SizedBox.square(dimension: 16),
        ),
        const SizedBox(width: 8),
        Text(accentColor.label),
      ],
    );
  }
}

String _languagePreferenceLabel(
  AppLocalizations localizations,
  AppLanguagePreference preference,
) {
  switch (preference) {
    case AppLanguagePreference.system:
      return localizations.languageSystem;
    case AppLanguagePreference.english:
      return localizations.languageEnglish;
    case AppLanguagePreference.turkish:
      return localizations.languageTurkish;
    case AppLanguagePreference.arabic:
      return localizations.languageArabic;
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    this.onRestartOnboarding,
    required this.isRefreshingLocalMetadata,
    this.onRefreshLocalMetadata,
    this.onClearLyricsSearchCache,
    this.onUploadLyricsSearchEndpointToSync,
    this.onImportLyricsSearchEndpointFromSync,
    required this.lyricsSearchCacheLifetime,
    this.onLyricsSearchCacheLifetimeChanged,
  });

  final VoidCallback? onRestartOnboarding;
  final bool isRefreshingLocalMetadata;
  final Future<void> Function()? onRefreshLocalMetadata;
  final Future<void> Function()? onClearLyricsSearchCache;
  final Future<void> Function()? onUploadLyricsSearchEndpointToSync;
  final Future<void> Function()? onImportLyricsSearchEndpointFromSync;
  final Duration lyricsSearchCacheLifetime;
  final ValueChanged<Duration>? onLyricsSearchCacheLifetimeChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final player = context.watch<PlayerController>();
    final library = context.watch<LibraryStore>();
    // HomeScreen is also used directly by focused widget tests and embedders.
    // The app shell supplies this shared log, while those narrow surfaces can
    // remain independent of diagnostics capture.
    final diagnostics = context.watch<LocalDiagnosticLog?>();
    final folderWatcher = context.watch<LocalFolderWatchStore?>();
    final lyricsTranslation = context.watch<LyricsTranslationSettingsStore?>();
    final lyricsSearchEndpoint = context
        .watch<LyricsSearchEndpointSettingsStore?>();
    final librarySync = context.watch<LibrarySyncStore?>();
    final listenBrainz = context.watch<ListenBrainzScrobblingStore?>();
    final duplicateGroups = library.duplicateTrackGroups();
    final offlineQueue = library.offlineCacheQueue;
    final offlineCacheLimitBytes = library.offlineCacheLimitBytes;
    final pendingOfflineQueue = offlineQueue
        .where(_canProcessOfflineCacheEntry)
        .toList(growable: false);
    final pausedOfflineQueueCount = offlineQueue
        .where((entry) => entry.status == OfflineCacheEntryStatus.paused)
        .length;
    final localTrackCount = library.tracks
        .where(
          (track) =>
              track.sourceId == 'local' &&
              track.localPath != null &&
              track.localPath!.isNotEmpty,
        )
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Options', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (onRestartOnboarding != null)
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('Run setup again'),
            subtitle: const Text(
              'Choose a local-library or legal-source starting point.',
            ),
            onTap: onRestartOnboarding,
          ),
        SwitchListTile(
          title: const Text('Shuffle queue'),
          subtitle: const Text(
            'Randomize playback order when supported by the queue.',
          ),
          value: player.shuffleEnabled,
          onChanged: player.setShuffleEnabled,
        ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            secondary: const Icon(Icons.minimize_outlined),
            title: Text(localizations.desktopTrayMinimizeOnClose),
            subtitle: Text(localizations.desktopTrayMinimizeOnCloseDescription),
            value: library.desktopMinimizeToTray,
            onChanged: (enabled) =>
                unawaited(library.setDesktopMinimizeToTray(enabled)),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            key: const Key('desktop-artist-release-refresh'),
            secondary: const Icon(Icons.new_releases_outlined),
            title: const Text('Refresh followed artists in tray'),
            subtitle: const Text(
              'While minimized, check MusicBrainz at most daily using up to four followed artist names.',
            ),
            value: library.desktopArtistReleaseRefreshEnabled,
            onChanged: library.offlineModeEnabled
                ? null
                : (enabled) => unawaited(
                    library.setDesktopArtistReleaseRefreshEnabled(enabled),
                  ),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            key: const Key('desktop-tray-action-previous'),
            secondary: const Icon(Icons.skip_previous_outlined),
            title: Text(localizations.desktopTrayPrevious),
            subtitle: Text(localizations.desktopTrayPreviousDescription),
            value: library.desktopTrayTransportActions.contains(
              DesktopTrayTransportAction.previous,
            ),
            onChanged: (enabled) => unawaited(
              library.setDesktopTrayTransportActionEnabled(
                DesktopTrayTransportAction.previous,
                enabled,
              ),
            ),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            key: const Key('desktop-tray-action-play-pause'),
            secondary: const Icon(Icons.play_circle_outline),
            title: Text(localizations.desktopTrayPlayPause),
            subtitle: Text(localizations.desktopTrayPlayPauseDescription),
            value: library.desktopTrayTransportActions.contains(
              DesktopTrayTransportAction.togglePlayPause,
            ),
            onChanged: (enabled) => unawaited(
              library.setDesktopTrayTransportActionEnabled(
                DesktopTrayTransportAction.togglePlayPause,
                enabled,
              ),
            ),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            key: const Key('desktop-tray-action-next'),
            secondary: const Icon(Icons.skip_next_outlined),
            title: Text(localizations.desktopTrayNext),
            subtitle: Text(localizations.desktopTrayNextDescription),
            value: library.desktopTrayTransportActions.contains(
              DesktopTrayTransportAction.next,
            ),
            onChanged: (enabled) => unawaited(
              library.setDesktopTrayTransportActionEnabled(
                DesktopTrayTransportAction.next,
                enabled,
              ),
            ),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          ListTile(
            key: const Key('desktop-density-preference'),
            leading: const Icon(Icons.density_medium_outlined),
            title: const Text('Desktop density'),
            subtitle: const Text(
              'Choose how much space desktop controls and lists use.',
            ),
            trailing: DropdownButton<DesktopDensityPreference>(
              value: library.desktopDensityPreference,
              items: DesktopDensityPreference.values
                  .map(
                    (preference) => DropdownMenuItem<DesktopDensityPreference>(
                      value: preference,
                      child: Text(preference.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (preference) {
                if (preference != null) {
                  unawaited(library.setDesktopDensityPreference(preference));
                }
              },
            ),
          ),
        if (player.supportsPitch)
          ListTile(
            key: const Key('playback-pitch-setting'),
            title: const Text('Playback pitch'),
            subtitle: const Text(
              'Shifts pitch independently from playback speed on this device.',
            ),
            trailing: DropdownButton<double>(
              value: player.defaultPlaybackPitch,
              items: <DropdownMenuItem<double>>[
                for (final pitch in PlayerController.supportedPlaybackPitches)
                  DropdownMenuItem<double>(
                    value: pitch,
                    child: Text(
                      pitch == pitch.roundToDouble()
                          ? '${pitch.toStringAsFixed(0)}x'
                          : '${pitch}x',
                    ),
                  ),
              ],
              onChanged: (pitch) {
                if (pitch != null) {
                  unawaited(player.setPlaybackPitch(pitch));
                }
              },
            ),
          ),
        ListTile(
          title: const Text('Repeat mode'),
          subtitle: Text(player.loopMode.name),
          trailing: DropdownButton<LoopMode>(
            value: player.loopMode,
            items: const <DropdownMenuItem<LoopMode>>[
              DropdownMenuItem(value: LoopMode.off, child: Text('Off')),
              DropdownMenuItem(value: LoopMode.one, child: Text('One')),
              DropdownMenuItem(value: LoopMode.all, child: Text('All')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                player.setLoopMode(mode);
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Playback speed'),
          subtitle: const Text(
            'Sets the default for future playback; track overrides stay separate.',
          ),
          trailing: DropdownButton<double>(
            value: player.defaultPlaybackSpeed,
            items: <DropdownMenuItem<double>>[
              for (final speed in PlayerController.supportedPlaybackSpeeds)
                DropdownMenuItem<double>(
                  value: speed,
                  child: Text(
                    speed == speed.roundToDouble()
                        ? '${speed.toStringAsFixed(0)}x'
                        : '${speed}x',
                  ),
                ),
            ],
            onChanged: (speed) async {
              if (speed == null) {
                return;
              }
              await player.setPlaybackSpeed(speed);
              final current = player.current;
              final override = current == null
                  ? null
                  : library.playbackSpeedForTrack(current.id);
              if (override != null) {
                await player.setTemporaryPlaybackSpeed(override);
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Skip backward'),
          subtitle: const Text(
            'Interval used by the full player rewind control.',
          ),
          trailing: DropdownButton<Duration>(
            value: player.skipBackwardInterval,
            items: <DropdownMenuItem<Duration>>[
              for (final interval in PlayerController.supportedSkipIntervals)
                DropdownMenuItem<Duration>(
                  value: interval,
                  child: Text('${interval.inSeconds}s'),
                ),
            ],
            onChanged: (interval) {
              if (interval != null) {
                unawaited(player.setSkipBackwardInterval(interval));
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Skip forward'),
          subtitle: const Text(
            'Interval used by the full player forward control.',
          ),
          trailing: DropdownButton<Duration>(
            value: player.skipForwardInterval,
            items: <DropdownMenuItem<Duration>>[
              for (final interval in PlayerController.supportedSkipIntervals)
                DropdownMenuItem<Duration>(
                  value: interval,
                  child: Text('${interval.inSeconds}s'),
                ),
            ],
            onChanged: (interval) {
              if (interval != null) {
                unawaited(player.setSkipForwardInterval(interval));
              }
            },
          ),
        ),
        if (player.supportsSkipSilence)
          SwitchListTile(
            key: const Key('skip-silence-setting'),
            secondary: const Icon(Icons.graphic_eq_outlined),
            title: const Text('Skip silence'),
            subtitle: const Text(
              'Shortens quiet passages during playback on this device.',
            ),
            value: player.skipSilenceEnabled,
            onChanged: (enabled) =>
                unawaited(player.setSkipSilenceEnabled(enabled)),
          ),
        SwitchListTile(
          key: const Key('skip-failed-tracks-setting'),
          secondary: const Icon(Icons.skip_next_outlined),
          title: const Text('Skip failed tracks'),
          subtitle: const Text(
            'Advances through the queue when the current track cannot play.',
          ),
          value: player.skipFailedTracksEnabled,
          onChanged: (enabled) =>
              unawaited(player.setSkipFailedTracksEnabled(enabled)),
        ),
        if (lyricsTranslation != null)
          ListTile(
            key: const Key('lyrics-translation-settings'),
            leading: const Icon(Icons.translate_outlined),
            title: const Text('Lyrics translation'),
            subtitle: Text(
              lyricsTranslation.isConfigured
                  ? 'Self-hosted service: ${lyricsTranslation.endpoint!.host} to ${lyricsTranslation.targetLanguage}.'
                  : 'Configure a self-hosted LibreTranslate-compatible service.',
            ),
            onTap: () => unawaited(_configureLyricsTranslation(context)),
            trailing: lyricsTranslation.isConfigured
                ? IconButton(
                    tooltip: 'Remove lyrics translation service',
                    onPressed: () =>
                        unawaited(_removeLyricsTranslation(context)),
                    icon: const Icon(Icons.delete_outline),
                  )
                : const Icon(Icons.chevron_right),
          ),
        if (lyricsSearchEndpoint != null)
          ListTile(
            key: const Key('lyrics-search-endpoint-settings'),
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('Lyrics search service'),
            subtitle: Text(
              lyricsSearchEndpoint.isConfigured
                  ? 'Self-hosted LRCLIB-compatible service: ${lyricsSearchEndpoint.endpoint!.host}.'
                  : 'Use public LRCLIB or configure a self-hosted compatible service.',
            ),
            onTap: () => unawaited(_configureLyricsSearchEndpoint(context)),
            trailing: lyricsSearchEndpoint.isConfigured
                ? IconButton(
                    tooltip: 'Use public LRCLIB for lyrics search',
                    onPressed: () =>
                        unawaited(_removeLyricsSearchEndpoint(context)),
                    icon: const Icon(Icons.delete_outline),
                  )
                : const Icon(Icons.chevron_right),
          ),
        if (lyricsSearchEndpoint?.isConfigured == true &&
            librarySync?.isConfigured == true)
          ListTile(
            key: const Key('upload-lyrics-search-endpoint-to-sync'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Upload lyrics search service'),
            subtitle: const Text(
              'Sends only the HTTPS endpoint to your sync server; cached lyrics stay local.',
            ),
            enabled:
                !library.offlineModeEnabled &&
                onUploadLyricsSearchEndpointToSync != null,
            onTap:
                !library.offlineModeEnabled &&
                    onUploadLyricsSearchEndpointToSync != null
                ? () => unawaited(onUploadLyricsSearchEndpointToSync!())
                : null,
          ),
        if (librarySync?.isConfigured == true)
          ListTile(
            key: const Key('import-lyrics-search-endpoint-from-sync'),
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Import lyrics search service'),
            subtitle: const Text(
              'Replaces this device\'s configured service; no credentials are transferred.',
            ),
            enabled:
                !library.offlineModeEnabled &&
                onImportLyricsSearchEndpointFromSync != null,
            onTap:
                !library.offlineModeEnabled &&
                    onImportLyricsSearchEndpointFromSync != null
                ? () => unawaited(onImportLyricsSearchEndpointFromSync!())
                : null,
          ),
        if (listenBrainz != null)
          ListTile(
            key: const Key('listenbrainz-settings'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('ListenBrainz scrobbling'),
            subtitle: Text(
              listenBrainz.isConfigured
                  ? 'Completed listens are sent to ListenBrainz${listenBrainz.userName == null ? '' : ' for ${listenBrainz.userName}'}. Pausing listening history also pauses submissions.'
                  : 'Optionally submit completed listens to your ListenBrainz account.',
            ),
            onTap: () => unawaited(_configureListenBrainz(context)),
            trailing: listenBrainz.isConfigured
                ? IconButton(
                    tooltip: 'Disconnect ListenBrainz',
                    onPressed: () => unawaited(_removeListenBrainz(context)),
                    icon: const Icon(Icons.delete_outline),
                  )
                : const Icon(Icons.chevron_right),
          ),
        if (listenBrainz?.isConfigured == true)
          if (listenBrainz!.pendingListenCount > 0)
            ListTile(
              key: const Key('listenbrainz-retry-pending'),
              leading: const Icon(Icons.refresh_outlined),
              title: Text(
                'Retry ${listenBrainz.pendingListenCount} pending ListenBrainz listen${listenBrainz.pendingListenCount == 1 ? '' : 's'}',
              ),
              subtitle: const Text(
                'Retries saved completed-listen metadata in the foreground.',
              ),
              trailing: listenBrainz.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: listenBrainz.submitting
                  ? null
                  : () => unawaited(_retryListenBrainzPending(context)),
            ),
        if (listenBrainz?.isConfigured == true)
          SwitchListTile(
            key: const Key('listenbrainz-background-retry'),
            secondary: const Icon(Icons.schedule_outlined),
            title: const Text('Retry pending listens in background'),
            subtitle: const Text(
              'Disabled by default. Android and iOS may retry saved listen metadata after you leave the app; Offline mode and paused history stop it.',
            ),
            value: listenBrainz!.backgroundRetryEnabled,
            onChanged: listenBrainz.submitting
                ? null
                : (enabled) => unawaited(
                    _setListenBrainzBackgroundRetry(context, enabled),
                  ),
          ),
        if (listenBrainz?.isConfigured == true)
          ListTile(
            key: const Key('listenbrainz-import-history'),
            leading: const Icon(Icons.history_outlined),
            title: const Text('Import ListenBrainz history'),
            subtitle: const Text(
              'Match your 100 most recent listens to tracks already in this library.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_importListenBrainzHistory(context)),
          ),
        if (listenBrainz?.lastError != null)
          ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('ListenBrainz needs attention'),
            subtitle: Text(listenBrainz!.lastError!),
          ),
        ListTile(
          leading: Icon(
            player.volume == 0
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
          ),
          title: const Text('Playback volume'),
          subtitle: Slider(
            value: player.volume,
            semanticFormatterCallback: (value) =>
                'Playback volume ${PlayerController.formatVolume(value)}',
            onChanged: player.isSleepFadeActive
                ? null
                : (value) => unawaited(player.previewVolume(value)),
            onChangeEnd: player.isSleepFadeActive
                ? null
                : (value) => unawaited(player.setVolume(value)),
          ),
          trailing: Text(PlayerController.formatVolume(player.volume)),
        ),
        if (player.supportsCrossfade)
          ListTile(
            leading: const Icon(Icons.swap_calls_outlined),
            title: const Text('Crossfade'),
            subtitle: const Text(
              'Blends consecutive tracks when shuffle is off and duration is known.',
            ),
            trailing: DropdownButton<Duration>(
              value: player.crossfadeDuration,
              items: <DropdownMenuItem<Duration>>[
                for (final duration
                    in PlayerController.supportedCrossfadeDurations)
                  DropdownMenuItem<Duration>(
                    value: duration,
                    child: Text(
                      duration == Duration.zero
                          ? 'Off'
                          : '${duration.inSeconds}s',
                    ),
                  ),
              ],
              onChanged: player.isSleepFadeActive
                  ? null
                  : (duration) {
                      if (duration != null) {
                        unawaited(player.setCrossfadeDuration(duration));
                      }
                    },
            ),
          ),
        if (player.supportsEqualizer ||
            player.supportsLoudnessEnhancer ||
            player.supportsVirtualizer)
          AudioEffectsSettingsTile(player: player),
        SwitchListTile(
          secondary: const Icon(Icons.graphic_eq_outlined),
          title: const Text('Loudness normalization'),
          subtitle: const Text('Use native ReplayGain tags when available.'),
          value: player.loudnessNormalizationEnabled,
          onChanged: player.isSleepFadeActive
              ? null
              : (enabled) =>
                    unawaited(player.setLoudnessNormalizationEnabled(enabled)),
        ),
        ListTile(
          leading: const Icon(Icons.album_outlined),
          title: const Text('ReplayGain source'),
          subtitle: const Text('Album gain keeps each album\'s dynamics.'),
          trailing: DropdownButton<ReplayGainMode>(
            value: player.replayGainMode,
            items: const <DropdownMenuItem<ReplayGainMode>>[
              DropdownMenuItem(
                value: ReplayGainMode.track,
                child: Text('Track'),
              ),
              DropdownMenuItem(
                value: ReplayGainMode.album,
                child: Text('Album'),
              ),
            ],
            onChanged:
                !player.loudnessNormalizationEnabled || player.isSleepFadeActive
                ? null
                : (mode) {
                    if (mode != null) {
                      unawaited(player.setReplayGainMode(mode));
                    }
                  },
          ),
        ),
        if (localTrackCount > 0)
          ListTile(
            key: const Key('refresh-local-metadata'),
            leading: const Icon(Icons.refresh_outlined),
            title: const Text('Refresh local metadata'),
            subtitle: Text(
              isRefreshingLocalMetadata
                  ? 'Scanning local files and sidecars...'
                  : 'Rescan $localTrackCount local file(s) without removing unavailable tracks.',
            ),
            trailing: isRefreshingLocalMetadata
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: isRefreshingLocalMetadata || onRefreshLocalMetadata == null
                ? null
                : () => unawaited(onRefreshLocalMetadata!()),
          ),
        if (library.watchedLocalFolderPaths.isNotEmpty) ...<Widget>[
          const Divider(),
          Text(
            'Watched folders',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          for (final rootPath in library.watchedLocalFolderPaths)
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(
                p.basename(rootPath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                folderWatcher?.errorFor(rootPath) ??
                    (folderWatcher?.isRefreshing(rootPath) ?? false
                        ? 'Refreshing library changes...'
                        : rootPath),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Refresh folder',
                    onPressed:
                        folderWatcher == null ||
                            folderWatcher.isRefreshing(rootPath)
                        ? null
                        : () => folderWatcher.refresh(rootPath),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Stop watching folder',
                    onPressed: () =>
                        unawaited(library.unwatchLocalFolder(rootPath)),
                    icon: const Icon(Icons.folder_off_outlined),
                  ),
                ],
              ),
            ),
        ],
        const Divider(),
        if (diagnostics != null)
          ListTile(
            key: const Key('local-diagnostic-log'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Local diagnostics'),
            subtitle: Text(
              diagnostics.persistenceError
                  ? 'Diagnostic storage or legacy report cleanup failed. Clear to retry.'
                  : diagnostics.entries.isEmpty
                  ? 'No reports. Nothing is sent from this device.'
                  : '${diagnostics.entries.length} local report(s). Nothing is sent automatically.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Export local diagnostics',
                  onPressed: diagnostics.entries.isEmpty
                      ? null
                      : () => unawaited(
                          _exportLocalDiagnostics(context, diagnostics),
                        ),
                  icon: const Icon(Icons.save_alt_outlined),
                ),
                IconButton(
                  tooltip: 'Clear local diagnostics',
                  onPressed:
                      diagnostics.entries.isEmpty &&
                          !diagnostics.persistenceError
                      ? null
                      : () => unawaited(
                          _clearLocalDiagnostics(context, diagnostics),
                        ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(localizations.language),
          subtitle: Text(
            _languagePreferenceLabel(localizations, library.languagePreference),
          ),
          trailing: DropdownButton<AppLanguagePreference>(
            value: library.languagePreference,
            items: <DropdownMenuItem<AppLanguagePreference>>[
              for (final preference in AppLanguagePreference.values)
                DropdownMenuItem<AppLanguagePreference>(
                  value: preference,
                  child: Text(
                    _languagePreferenceLabel(localizations, preference),
                  ),
                ),
            ],
            onChanged: (preference) {
              if (preference != null) {
                unawaited(library.setLanguagePreference(preference));
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Theme'),
          subtitle: Text(library.themePreference.label),
          trailing: DropdownButton<AppThemePreference>(
            value: library.themePreference,
            items: const <DropdownMenuItem<AppThemePreference>>[
              DropdownMenuItem(
                value: AppThemePreference.system,
                child: Text('System'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.light,
                child: Text('Light'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.dark,
                child: Text('Dark'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.amoled,
                child: Text('AMOLED'),
              ),
            ],
            onChanged: (preference) {
              if (preference != null) {
                unawaited(library.setThemePreference(preference));
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.color_lens_outlined),
          title: const Text('Accent color'),
          subtitle: Text(library.accentColor.label),
          trailing: DropdownButton<AppAccentColor>(
            value: library.accentColor,
            items: <DropdownMenuItem<AppAccentColor>>[
              for (final accentColor in AppAccentColor.values)
                DropdownMenuItem<AppAccentColor>(
                  value: accentColor,
                  child: _AccentColorDropdownLabel(accentColor: accentColor),
                ),
            ],
            onChanged: (accentColor) {
              if (accentColor != null) {
                unawaited(library.setAccentColor(accentColor));
              }
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.favorite_outline),
          title: const Text('Use favorites in For you'),
          subtitle: const Text(
            'Let favorite tracks, artists, albums, and genres shape recommendations.',
          ),
          value: library.recommendationFavoriteSignalsEnabled,
          onChanged: (value) {
            unawaited(library.setRecommendationFavoriteSignalsEnabled(value));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.history),
          title: const Text('Use listening history in For you'),
          subtitle: const Text(
            'Let recent plays, play counts, and unplayed status shape recommendations.',
          ),
          value: library.recommendationHistorySignalsEnabled,
          onChanged: (value) {
            unawaited(library.setRecommendationHistorySignalsEnabled(value));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pause_circle_outline),
          title: const Text('Pause listening history'),
          subtitle: const Text(
            'Stop saving new plays and resume progress until this is turned off.',
          ),
          value: library.pauseListeningHistory,
          onChanged: (value) {
            unawaited(library.setPauseListeningHistory(value));
          },
        ),
        if (!kIsWeb && supportsPlatformAudioRoutePicker(defaultTargetPlatform))
          ListTile(
            key: const Key('audio-output-picker'),
            leading: const Icon(Icons.speaker_group_outlined),
            title: const Text('Audio output'),
            subtitle: const Text('Choose an available system playback route.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_showMobileAudioRoutePicker(context)),
          ),
        if (!kIsWeb &&
            supportsDesktopAudioOutputSettings(defaultTargetPlatform))
          ListTile(
            key: const Key('desktop-audio-output-settings'),
            leading: const Icon(Icons.speaker_group_outlined),
            title: const Text('Audio output settings'),
            subtitle: const Text(
              'Choose the Windows playback device and output controls.',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => unawaited(_showDesktopAudioOutputSettings(context)),
          ),
        if (!kIsWeb && Platform.isAndroid)
          ListTile(
            key: const Key('android-pinned-shortcut'),
            leading: const Icon(Icons.push_pin_outlined),
            title: const Text('Pin playback shortcut'),
            trailing: PopupMenuButton<AndroidPinnedShortcut>(
              key: const Key('android-pinned-shortcut-menu'),
              tooltip: 'Choose a playback shortcut to pin',
              icon: const Icon(Icons.add),
              onSelected: (shortcut) =>
                  unawaited(_requestAndroidPinnedShortcut(context, shortcut)),
              itemBuilder: (context) => <PopupMenuEntry<AndroidPinnedShortcut>>[
                for (final shortcut in AndroidPinnedShortcut.values)
                  PopupMenuItem<AndroidPinnedShortcut>(
                    value: shortcut,
                    child: Text(shortcut.label),
                  ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.lyrics_outlined),
          title: const Text('Cached lyrics searches'),
          subtitle: const Text(
            'Clear stored LRCLIB search results from this device.',
          ),
          trailing: IconButton(
            tooltip: 'Clear cached lyrics searches',
            onPressed: onClearLyricsSearchCache == null
                ? null
                : () => unawaited(onClearLyricsSearchCache!()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Lyrics cache retention'),
          subtitle: const Text(
            'How long cached searches remain available offline.',
          ),
          trailing: DropdownButton<Duration>(
            value: lyricsSearchCacheLifetime,
            items: <DropdownMenuItem<Duration>>[
              for (final retention in supportedLyricsSearchCacheLifetimes)
                DropdownMenuItem<Duration>(
                  value: retention,
                  child: Text('${retention.inDays} day(s)'),
                ),
            ],
            onChanged: onLyricsSearchCacheLifetimeChanged == null
                ? null
                : (retention) {
                    if (retention != null) {
                      onLyricsSearchCacheLifetimeChanged!(retention);
                    }
                  },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.cloud_off_outlined),
          title: const Text('Offline mode'),
          subtitle: const Text(
            'Pause network-backed source searches, feed refreshes, and stream playback.',
          ),
          value: library.offlineModeEnabled,
          onChanged: (value) {
            unawaited(library.setOfflineModeEnabled(value));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.download_for_offline_outlined),
          title: const Text('Automatic foreground downloads'),
          subtitle: const Text(
            'Process approved queued items one at a time while the app is open.',
          ),
          value: library.automaticOfflineQueueEnabled,
          onChanged: library.offlineModeEnabled
              ? null
              : (value) {
                  unawaited(library.setAutomaticOfflineQueueEnabled(value));
                },
        ),
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('Offline queue'),
          subtitle: Text(
            offlineQueue.isEmpty
                ? 'No queued cache or download requests'
                : '${offlineQueue.length} queued cache/download request(s), '
                      '${pendingOfflineQueue.length} ready, '
                      '$pausedOfflineQueueCount paused',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Cache queued media',
                onPressed: pendingOfflineQueue.isEmpty
                    ? null
                    : () => unawaited(
                        _processOfflineCacheEntries(
                          context,
                          pendingOfflineQueue,
                        ),
                      ),
                icon: const Icon(Icons.cloud_download_outlined),
              ),
              IconButton(
                tooltip: 'Clear offline queue',
                onPressed: offlineQueue.isEmpty
                    ? null
                    : () => unawaited(library.clearOfflineCacheQueue()),
                icon: const Icon(Icons.clear_all),
              ),
            ],
          ),
        ),
        // ListView mounts this row lazily. Start I/O only after its error
        // handler can be attached, not while constructing off-screen children.
        Builder(
          builder: (context) => FutureBuilder<OfflineCacheUsage>(
            future: _offlineCacheUsage(offlineQueue),
            builder: (context, snapshot) {
              final usage = snapshot.data;
              final offlineCacheLimitLabel = _formatByteCount(
                offlineCacheLimitBytes,
              );
              final canTrim =
                  usage != null && usage.byteCount > offlineCacheLimitBytes;
              final canClear = usage != null && usage.byteCount > 0;
              final subtitle = snapshot.hasError
                  ? 'Could not read cache usage.'
                  : usage == null
                  ? 'Calculating private cache usage...'
                  : '${_formatByteCount(usage.byteCount)} across '
                        '${usage.cachedEntryCount} cached item(s), '
                        '${_formatByteCount(usage.partialByteCount)} partial, '
                        '${_formatByteCount(usage.unindexedByteCount)} unindexed · '
                        'Limit: $offlineCacheLimitLabel';

              return ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Offline cache storage'),
                subtitle: Text(subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Set cache limit',
                      onPressed: () =>
                          unawaited(_showOfflineCacheLimitDialog(context)),
                      icon: const Icon(Icons.tune_outlined),
                    ),
                    IconButton(
                      tooltip: 'Trim cache to $offlineCacheLimitLabel',
                      onPressed: canTrim
                          ? () => unawaited(
                              _trimOfflineCache(
                                context,
                                offlineCacheLimitBytes,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                    IconButton(
                      tooltip: 'Clear cached media',
                      onPressed: canClear
                          ? () => unawaited(_trimOfflineCache(context, 0))
                          : null,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        for (final sourceId in _offlineCacheProviderIds(offlineQueue))
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text('Provider cache limit: $sourceId'),
            subtitle: Text(_offlineCacheProviderLimitLabel(library, sourceId)),
            trailing: IconButton(
              tooltip: 'Set $sourceId cache limit',
              onPressed: () => unawaited(
                _showOfflineCacheProviderLimitDialog(context, sourceId),
              ),
              icon: const Icon(Icons.tune_outlined),
            ),
          ),
        for (final entry in offlineQueue.take(5))
          ListTile(
            dense: true,
            leading: Icon(_offlineCacheEntryIcon(entry)),
            title: Text(
              entry.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _offlineCacheEntrySubtitle(entry),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Cache media',
                  onPressed: _canProcessOfflineCacheEntry(entry)
                      ? () => unawaited(
                          _processOfflineCacheEntries(
                            context,
                            <OfflineCacheEntry>[entry],
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.cloud_download_outlined),
                ),
                IconButton(
                  tooltip: _canResumeOfflineCacheEntry(entry)
                      ? 'Resume offline request'
                      : entry.status == OfflineCacheEntryStatus.processing
                      ? 'Pause active offline request'
                      : 'Pause offline request',
                  onPressed: _canResumeOfflineCacheEntry(entry)
                      ? () =>
                            unawaited(library.resumeOfflineCacheEntry(entry.id))
                      : _canPauseOfflineCacheEntry(entry)
                      ? () =>
                            unawaited(library.pauseOfflineCacheEntry(entry.id))
                      : null,
                  icon: Icon(
                    _canResumeOfflineCacheEntry(entry)
                        ? Icons.play_arrow_outlined
                        : Icons.pause_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Export cached media',
                  onPressed: _canExportOfflineCacheEntry(entry)
                      ? () =>
                            unawaited(_exportOfflineCacheEntry(context, entry))
                      : null,
                  icon: const Icon(Icons.file_download_outlined),
                ),
                IconButton(
                  tooltip: 'Remove from offline queue',
                  onPressed: () =>
                      unawaited(library.removeOfflineCacheEntry(entry.id)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if (offlineQueue.length > 5)
          ListTile(
            dense: true,
            leading: const Icon(Icons.more_horiz),
            title: Text('${offlineQueue.length - 5} more queued item(s)'),
          ),
        const Divider(),
        const LibrarySyncPanel(),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Export backup'),
          onTap: () => _showBackupExport(context),
        ),
        ListTile(
          leading: const Icon(Icons.restore_page_outlined),
          title: const Text('Restore backup'),
          onTap: () => _showBackupRestore(context),
        ),
        ListTile(
          leading: const Icon(Icons.merge_type_outlined),
          title: const Text('Resolve duplicates'),
          subtitle: Text(
            duplicateGroups.isEmpty
                ? 'No duplicate groups found'
                : '${duplicateGroups.length} duplicate group(s) found',
          ),
          enabled: library.loaded && duplicateGroups.isNotEmpty,
          onTap: library.loaded && duplicateGroups.isNotEmpty
              ? () => _showDuplicateResolver(context)
              : null,
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text(
            'No ads, no telemetry, no forced account in the core app.',
          ),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.screenshot_monitor_outlined),
          title: const Text('Block screenshots'),
          subtitle: const Text(
            'Prevent screenshots and screen recording on Android.',
          ),
          value: library.screenshotProtectionEnabled,
          onChanged: library.loaded
              ? (enabled) =>
                    unawaited(library.setScreenshotProtectionEnabled(enabled))
              : null,
        ),
        const ListTile(
          leading: Icon(Icons.balance_outlined),
          title: Text('Legal source policy'),
          subtitle: Text(
            'Provider adapters must use legal, documented, user-owned, or official APIs.',
          ),
        ),
      ],
    );
  }

  Future<OfflineCacheUsage> _offlineCacheUsage(
    List<OfflineCacheEntry> entries,
  ) async {
    final cacheRoot = await getApplicationDocumentsDirectory();
    return OfflineCacheManager(cacheRoot: cacheRoot).storageUsage(entries);
  }

  Future<void> _showOfflineCacheLimitDialog(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(
      text: library.offlineCacheLimitMegabytes.toString(),
    );

    int? parseLimit() {
      return int.tryParse(controller.text.trim());
    }

    try {
      final selectedLimit = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Offline cache limit'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
                helperText: 'Allowed range: 50-51200 MB',
              ),
              onSubmitted: (_) {
                Navigator.of(dialogContext).pop(parseLimit());
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(parseLimit());
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (!context.mounted || selectedLimit == null) {
        return;
      }

      await library.setOfflineCacheLimitMegabytes(selectedLimit);
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Offline cache limit set to '
            '${_formatByteCount(library.offlineCacheLimitBytes)}.',
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showOfflineCacheProviderLimitDialog(
    BuildContext context,
    String sourceId,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final currentLimit = library.offlineCacheProviderLimitMegabytesFor(
      sourceId,
    );
    final controller = TextEditingController(
      text: currentLimit?.toString() ?? '0',
    );

    int? parseLimit() {
      return int.tryParse(controller.text.trim());
    }

    try {
      final selectedLimit = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('$sourceId cache limit'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
                helperText: '0 clears quota. Allowed range: 1-51200 MB',
              ),
              onSubmitted: (_) {
                Navigator.of(dialogContext).pop(parseLimit());
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(parseLimit());
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (!context.mounted || selectedLimit == null) {
        return;
      }

      await library.setOfflineCacheProviderLimitMegabytes(
        sourceId,
        selectedLimit <= 0 ? null : selectedLimit,
      );
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$sourceId cache limit: '
            '${_offlineCacheProviderLimitLabel(library, sourceId)}.',
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _trimOfflineCache(BuildContext context, int maxBytes) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    if (maxBytes <= 0) {
      final confirmed = await confirmOfflineCacheClear(context);
      if (confirmed != true || !context.mounted) return;
    }
    try {
      final cacheRoot = await getApplicationDocumentsDirectory();
      final manager = OfflineCacheManager(cacheRoot: cacheRoot);
      if (maxBytes <= 0) {
        final result = await manager.clearPrivateMedia();
        await library.forgetClearedOfflineFiles(result.deletedPaths);
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Cleared ${_formatByteCount(result.byteCount)} of private media.'
              '${result.failedFileCount > 0 ? ' ${result.failedFileCount} file(s) could not be removed.' : ''}',
            ),
          ),
        );
        return;
      }
      final result = await manager.evictToSize(
        entries: library.offlineCacheQueue,
        maxBytes: maxBytes,
      );
      final reason =
          'Evicted to keep cache under ${_formatByteCount(maxBytes)}.';

      for (final entryId in result.evictedEntryIds) {
        await library.markOfflineCacheEntryEvicted(entryId, reason: reason);
      }

      if (!context.mounted) {
        return;
      }

      final actual = await manager.storageUsage(library.offlineCacheQueue);
      final message = actual.byteCount > maxBytes
          ? 'Private storage is still over the limit. Clear private media to remove partial and unindexed files.'
          : result.evictedEntryIds.isEmpty
          ? 'Offline cache already under ${_formatByteCount(maxBytes)}.'
          : 'Cleared ${_formatByteCount(result.evictedBytes)} from '
                '${result.evictedEntryIds.length} cached item(s).';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_offlineCacheErrorMessage(error))),
      );
    }
  }

  Future<void> _exportOfflineCacheEntry(
    BuildContext context,
    OfflineCacheEntry queuedEntry,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final entry = library.offlineCacheEntryById(queuedEntry.id) ?? queuedEntry;
    if (!_canExportOfflineCacheEntry(entry)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cache this media before exporting it.')),
      );
      return;
    }

    final cacheRoot = await getApplicationDocumentsDirectory();
    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final verifiedCache = await manager.verifyCachedMedia(entry: entry);
        final downloadUri = await AndroidSystemDownloadsExporter()
            .exportVerifiedFile(
              file: verifiedCache.file,
              displayName: manager.exportDisplayName(entry),
              byteCount: verifiedCache.byteCount,
              checksum: verifiedCache.checksum,
            );
        if (!context.mounted) {
          return;
        }
        if (downloadUri != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Saved ${manager.exportDisplayName(entry)} to Downloads.',
              ),
            ),
          );
          return;
        }
      }

      final destinationPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Export cached media',
      );
      if (!context.mounted || destinationPath == null) {
        return;
      }

      final export = await manager.exportCachedMedia(
        entry: entry,
        destinationDirectory: Directory(destinationPath),
      );
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${p.basename(export.file.path)} '
            '(${_formatByteCount(export.byteCount)}).',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_offlineCacheErrorMessage(error))),
      );
    }
  }

  Future<void> _processOfflineCacheEntries(
    BuildContext context,
    List<OfflineCacheEntry> entries,
  ) async {
    final library = context.read<LibraryStore>();
    final selfHosted = context.read<SelfHostedProviderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final cacheRoot = await getApplicationDocumentsDirectory();
    if (!context.mounted) {
      return;
    }

    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    var cached = 0;
    var failed = 0;
    var evicted = 0;
    var evictedBytes = 0;

    for (final queuedEntry in entries) {
      final entry = library.offlineCacheEntryById(queuedEntry.id);
      if (entry == null || !_canProcessOfflineCacheEntry(entry)) {
        continue;
      }

      await library.markOfflineCacheEntryProcessing(entry.id);
      final cancellationToken = OfflineCacheCancellationRegistry.instance
          .tokenFor(entry.id);
      final processingEntry = library.offlineCacheEntryById(entry.id) ?? entry;

      try {
        final resolvedTrack = await selfHosted.resolveTrack(
          processingEntry.track,
        );
        cancellationToken.throwIfCancelled();
        final materialization = await manager.materialize(
          processingEntry.copyWith(track: resolvedTrack),
          cancellationToken: cancellationToken,
          budget: offlineCacheBudget(library),
          maxBytes: offlineCacheTransferLimitBytes(
            library,
            resolvedTrack.sourceId,
          ),
        );
        if (library.offlineCacheEntryById(entry.id)?.status !=
            OfflineCacheEntryStatus.processing) {
          continue;
        }
        final cacheReason = materialization.expectedMediaChecksumVerified
            ? 'Cached ${_formatByteCount(materialization.byteCount)}; provider checksum verified.'
            : 'Cached ${_formatByteCount(materialization.byteCount)}; integrity check verified.';
        await library.markOfflineCacheEntryCached(
          entry.id,
          materialization.track,
          reason: cacheReason,
          byteCount: materialization.byteCount,
          checksum: materialization.checksum,
        );
        final evictionResult = await enforceOfflineCacheLimit(
          library: library,
          manager: manager,
        );
        evicted += evictionResult.evictedEntryIds.length;
        evictedBytes += evictionResult.evictedBytes;
        evicted += materialization.evictedEntryIds.length;
        evictedBytes += materialization.evictedBytes;
        cached += 1;
      } on OfflineCacheCancelled {
        // The Options control has already persisted the paused state.
      } on Object catch (error) {
        if (library.offlineCacheEntryById(entry.id)?.status ==
            OfflineCacheEntryStatus.paused) {
          continue;
        }
        await library.markOfflineCacheEntryFailed(
          entry.id,
          reason: _offlineCacheErrorMessage(error),
        );
        failed += 1;
      } finally {
        OfflineCacheCancellationRegistry.instance.release(
          entry.id,
          cancellationToken,
        );
      }
    }

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _offlineCacheResultMessage(
            cached: cached,
            failed: failed,
            evicted: evicted,
            evictedBytes: evictedBytes,
          ),
        ),
      ),
    );
  }

  Future<void> _showDuplicateResolver(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _DuplicateResolverSheet(),
    );
  }

  Future<void> _showBackupExport(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Save backup file'),
                subtitle: const Text(
                  'Write a portable JSON backup to a chosen location.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _saveBackupFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('View backup JSON'),
                subtitle: const Text('Inspect or copy the backup text.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showBackupJson(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveBackupFile(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final backupJson = library.exportBackupJson();
    final fileName = aetherTuneBackupFileName(DateTime.now());
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = encodeAetherTuneBackupFile(backupJson);
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save AetherTune backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>[aetherTuneBackupFileExtension],
        bytes: bytes,
      );
      if (outputPath == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save backup file: $error')),
      );
    }
  }

  Future<void> _showBackupJson(BuildContext context) async {
    final backupJson = context.read<LibraryStore>().exportBackupJson();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(backupJson)),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBackupRestore(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Choose backup file'),
                subtitle: const Text(
                  'Restore an AetherTune JSON backup from storage.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreBackupFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: const Text('Paste backup JSON'),
                subtitle: const Text('Restore from copied backup text.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreBackupFromText(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _restoreBackupFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>[aetherTuneBackupFileExtension],
      );
      if (files.isEmpty) {
        return;
      }

      final file = files.first;
      final bytes = await readPickedFileBytes(file);
      if (!context.mounted) {
        return;
      }
      await _restoreBackupJson(context, decodeAetherTuneBackupFile(bytes));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read backup file: $error')),
      );
    }
  }

  Future<void> _restoreBackupFromText(BuildContext context) async {
    final backupJson = await _promptForBackupJson(context);
    if (!context.mounted || backupJson == null) {
      return;
    }
    await _restoreBackupJson(context, backupJson);
  }

  Future<void> _restoreBackupJson(
    BuildContext context,
    String backupJson,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await library.restoreBackupJson(backupJson);
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(const SnackBar(content: Text('Restored backup.')));
  }

  Future<String?> _promptForBackupJson(BuildContext context) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Restore backup'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: const InputDecoration(labelText: 'Backup JSON'),
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 14,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
