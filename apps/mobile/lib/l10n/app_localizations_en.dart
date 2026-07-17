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
}
