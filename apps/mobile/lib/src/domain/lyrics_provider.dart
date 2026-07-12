import 'music_source_provider.dart';

final class LyricsSearchQuery {
  const LyricsSearchQuery({
    this.keywords = '',
    this.trackName = '',
    this.artistName = '',
    this.albumName = '',
    this.duration = Duration.zero,
  });

  final String keywords;
  final String trackName;
  final String artistName;
  final String albumName;
  final Duration duration;

  bool get hasSearchTerms =>
      keywords.trim().isNotEmpty || trackName.trim().isNotEmpty;
}

final class LyricsSearchResult {
  const LyricsSearchResult({
    required this.providerId,
    required this.providerName,
    required this.externalId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    required this.plainLyrics,
    required this.syncedLyrics,
    required this.sourceUri,
  });

  final String providerId;
  final String providerName;
  final String externalId;
  final String trackName;
  final String artistName;
  final String albumName;
  final Duration duration;
  final bool instrumental;
  final String plainLyrics;
  final String syncedLyrics;
  final Uri sourceUri;

  bool get hasSyncedLyrics => syncedLyrics.trim().isNotEmpty;
  bool get hasPlainLyrics => plainLyrics.trim().isNotEmpty;
  bool get isSelectable => hasSyncedLyrics || hasPlainLyrics;

  String? get preferredLyrics {
    final synced = syncedLyrics.trim();
    if (synced.isNotEmpty) {
      return synced;
    }

    final plain = plainLyrics.trim();
    return plain.isEmpty ? null : plain;
  }
}

abstract interface class LyricsProvider {
  String get id;
  String get name;
  String get description;
  ProviderPrivacyDisclosure get disclosure;

  Future<List<LyricsSearchResult>> search(LyricsSearchQuery query);
}

abstract interface class OfflineLyricsProvider {
  Future<List<LyricsSearchResult>> searchOffline(LyricsSearchQuery query);
}
