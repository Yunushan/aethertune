import 'track.dart';

/// Feature flags that a provider can expose to the app.
enum MusicSourceCapability {
  metadataSearch,
  radioDirectory,
  streamResolution,
  directPlayback,
  libraryBrowse,
  playlists,
  lyrics,
  syncedLyrics,
  offlineCache,
  downloads,
  subscriptions,
  recommendations,
  authentication,
}

extension MusicSourceCapabilityLabel on MusicSourceCapability {
  String get label {
    switch (this) {
      case MusicSourceCapability.metadataSearch:
        return 'Search';
      case MusicSourceCapability.radioDirectory:
        return 'Radio directory';
      case MusicSourceCapability.streamResolution:
        return 'Stream resolver';
      case MusicSourceCapability.directPlayback:
        return 'Playback';
      case MusicSourceCapability.libraryBrowse:
        return 'Library browse';
      case MusicSourceCapability.playlists:
        return 'Playlists';
      case MusicSourceCapability.lyrics:
        return 'Lyrics';
      case MusicSourceCapability.syncedLyrics:
        return 'Synced lyrics';
      case MusicSourceCapability.offlineCache:
        return 'Offline cache';
      case MusicSourceCapability.downloads:
        return 'Downloads';
      case MusicSourceCapability.subscriptions:
        return 'Subscriptions';
      case MusicSourceCapability.recommendations:
        return 'Recommendations';
      case MusicSourceCapability.authentication:
        return 'Authentication';
    }
  }
}

/// Privacy and permission disclosure for a provider adapter.
final class ProviderPrivacyDisclosure {
  const ProviderPrivacyDisclosure({
    this.networkDomains = const <String>[],
    this.dataSent = const <String>[],
    this.requiresUserCredentials = false,
    this.readsLocalFiles = false,
    this.cachesMedia = false,
    this.supportsDownloads = false,
  });

  final List<String> networkDomains;
  final List<String> dataSent;
  final bool requiresUserCredentials;
  final bool readsLocalFiles;
  final bool cachesMedia;
  final bool supportsDownloads;

  bool get usesNetwork => networkDomains.isNotEmpty;

  bool get isLocalOnly =>
      !usesNetwork &&
      !requiresUserCredentials &&
      dataSent.isEmpty;

  String get networkSummary {
    if (!usesNetwork) {
      return 'No network domains declared';
    }

    return networkDomains.join(', ');
  }
}

/// Implement this contract to add a legal source adapter.
///
/// Examples: local files, user-owned Jellyfin/Navidrome server, podcasts,
/// Internet Archive, Radio Browser, or any official/documented music API.
abstract interface class MusicSourceProvider {
  String get id;
  String get name;
  String get description;
  Set<MusicSourceCapability> get capabilities;
  ProviderPrivacyDisclosure get disclosure;

  /// Search metadata inside the provider.
  Future<List<Track>> search(String query);

  /// Resolve a playable URI. Providers can return null when the track is only
  /// metadata or when user authorization is required.
  Future<Uri?> resolveStream(Track track);
}
