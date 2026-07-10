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

enum OfflineMediaAction { cache, download }

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

extension OfflineMediaActionLabel on OfflineMediaAction {
  String get label {
    switch (this) {
      case OfflineMediaAction.cache:
        return 'Offline cache';
      case OfflineMediaAction.download:
        return 'Download';
    }
  }

  MusicSourceCapability get requiredCapability {
    switch (this) {
      case OfflineMediaAction.cache:
        return MusicSourceCapability.offlineCache;
      case OfflineMediaAction.download:
        return MusicSourceCapability.downloads;
    }
  }

  bool isDisclosedBy(ProviderPrivacyDisclosure disclosure) {
    switch (this) {
      case OfflineMediaAction.cache:
        return disclosure.cachesMedia;
      case OfflineMediaAction.download:
        return disclosure.supportsDownloads;
    }
  }

  String get disclosureRequirement {
    switch (this) {
      case OfflineMediaAction.cache:
        return 'media caching';
      case OfflineMediaAction.download:
        return 'downloads';
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
    this.cachesMetadata = false,
    this.cachesMedia = false,
    this.supportsDownloads = false,
  });

  final List<String> networkDomains;
  final List<String> dataSent;
  final bool requiresUserCredentials;
  final bool readsLocalFiles;
  final bool cachesMetadata;
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

final class OfflineMediaPolicyDecision {
  const OfflineMediaPolicyDecision({
    required this.action,
    required this.isAllowed,
    required this.reason,
    this.providerId,
    this.providerName,
  });

  final OfflineMediaAction action;
  final bool isAllowed;
  final String reason;
  final String? providerId;
  final String? providerName;
}

final class OfflineMediaPolicy {
  const OfflineMediaPolicy(this.providers);

  final List<MusicSourceProvider> providers;

  MusicSourceProvider? providerFor(String providerId) {
    for (final provider in providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }

    return null;
  }

  bool canCache(Track track) {
    return evaluate(track, OfflineMediaAction.cache).isAllowed;
  }

  bool canDownload(Track track) {
    return evaluate(track, OfflineMediaAction.download).isAllowed;
  }

  OfflineMediaPolicyDecision evaluate(
    Track track,
    OfflineMediaAction action,
  ) {
    if (track.localPath != null && track.localPath!.trim().isNotEmpty) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: true,
        reason: 'Local files are already available offline.',
      );
    }

    final provider = providerFor(track.sourceId);
    if (provider == null) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason: 'No provider is registered for ${track.sourceId}.',
      );
    }

    if (!provider.capabilities.contains(action.requiredCapability)) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason:
            '${provider.name} does not declare ${action.requiredCapability.label}.',
        providerId: provider.id,
        providerName: provider.name,
      );
    }

    if (!action.isDisclosedBy(provider.disclosure)) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason:
            '${provider.name} has not disclosed ${action.disclosureRequirement}.',
        providerId: provider.id,
        providerName: provider.name,
      );
    }

    if (!track.isPlayable &&
        !provider.capabilities.contains(
          MusicSourceCapability.streamResolution,
        )) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason: '${provider.name} cannot resolve a playable stream.',
        providerId: provider.id,
        providerName: provider.name,
      );
    }

    return OfflineMediaPolicyDecision(
      action: action,
      isAllowed: true,
      reason: '${provider.name} allows ${action.label.toLowerCase()}.',
      providerId: provider.id,
      providerName: provider.name,
    );
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
