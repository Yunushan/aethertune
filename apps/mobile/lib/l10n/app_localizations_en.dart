// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AetherTune';

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get playlists => 'Playlists';

  @override
  String get history => 'History';

  @override
  String get sources => 'Sources';

  @override
  String get options => 'Options';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTurkish => 'Turkish';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get loading => 'Loading AetherTune';

  @override
  String get setupSaveError => 'Could not save setup. Please try again.';

  @override
  String get welcomeTitle => 'Welcome to AetherTune';

  @override
  String get welcomeDescription =>
      'Start with music you control, or choose a legal source. You can change every choice later in Options.';

  @override
  String get localLibraryTitle => 'Set up a local library';

  @override
  String get localLibraryDescription =>
      'Import audio files or a folder, then keep watched folders in sync while the app is open.';

  @override
  String get openLibrary => 'Open Library';

  @override
  String get importAudio => 'Import audio';

  @override
  String get scanningSelectedAudio => 'Scanning selected audio...';

  @override
  String get scanningAudioFolder => 'Scanning audio folder...';

  @override
  String get legalSourcesTitle => 'Explore legal sources';

  @override
  String get legalSourcesDescription =>
      'Add podcast RSS feeds, browse Radio Browser, Internet Archive, or connect your own supported media server.';

  @override
  String get openSources => 'Open Sources';

  @override
  String get selfHostedLibraryTitle => 'Connect your music server';

  @override
  String get selfHostedLibraryDescription =>
      'Add a Jellyfin or Navidrome / Subsonic library using a secure, tested connection.';

  @override
  String get connectServer => 'Connect server';

  @override
  String get privacyFirstTitle => 'Privacy first';

  @override
  String get privacyFirstDescription =>
      'AetherTune has no telemetry. Network providers disclose the domains they contact before use.';

  @override
  String get startAtHome => 'Start at Home';

  @override
  String get skipSetup => 'Skip setup';

  @override
  String get desktopTrayMinimizeOnClose => 'Minimize to tray on close';

  @override
  String get desktopTrayMinimizeOnCloseDescription =>
      'Keep playback running in the system tray until you choose Quit.';

  @override
  String get desktopTrayPrevious => 'Previous in tray menu';

  @override
  String get desktopTrayPreviousDescription =>
      'Show a Previous command beside the always available Show and Quit actions.';

  @override
  String get desktopTrayPlayPause => 'Play / Pause in tray menu';

  @override
  String get desktopTrayPlayPauseDescription =>
      'Show a playback toggle beside the always available Show and Quit actions.';

  @override
  String get desktopTrayNext => 'Next in tray menu';

  @override
  String get desktopTrayNextDescription =>
      'Show a Next command beside the always available Show and Quit actions.';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get sleepTimerActive => 'Sleep timer active';

  @override
  String get sleepTimerStopsAtEnd =>
      'Playback stops at the end of this track.';

  @override
  String sleepTimerStopsIn(String remaining) => 'Playback stops in $remaining.';

  @override
  String get sleepTimerLessThanOneMinute => 'Less than 1 minute';

  @override
  String sleepTimerMinutes(int count) {
    return intl.Intl.plural(
      count,
      one: '1 minute',
      other: '$count minutes',
      locale: localeName,
    );
  }

  @override
  String sleepTimerHours(int count) {
    return intl.Intl.plural(
      count,
      one: '1 hour',
      other: '$count hours',
      locale: localeName,
    );
  }

  @override
  String get targetLanguage => 'Target language';

  @override
  String get translatingLyrics => 'Translating lyrics...';

  @override
  String get translatedLyrics => 'Translated lyrics';

  @override
  String translatedLyricsForLanguage(String language) =>
      'Target language: $language';

  @override
  String get copyTranslatedLyrics => 'Copy translated lyrics';

  @override
  String get translatedLyricsCopied => 'Translated lyrics copied.';

  @override
  String couldNotTranslateLyrics(String error) =>
      'Could not translate lyrics: $error';
}
