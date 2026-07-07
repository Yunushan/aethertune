import 'track.dart';

final class PodcastSubscription {
  PodcastSubscription({
    required this.id,
    required this.feedUrl,
    required this.title,
    this.description = '',
    this.author = '',
    this.artworkUri,
    DateTime? addedAt,
    this.lastFetchedAt,
    this.lastFetchError = '',
  }) : addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String feedUrl;
  final String title;
  final String description;
  final String author;
  final Uri? artworkUri;
  final DateTime addedAt;
  final DateTime? lastFetchedAt;
  final String lastFetchError;

  bool isRefreshDue(
    DateTime now, {
    Duration refreshInterval = defaultPodcastRefreshInterval,
  }) {
    final fetchedAt = lastFetchedAt;
    if (fetchedAt == null) {
      return true;
    }

    return now.difference(fetchedAt) >= refreshInterval;
  }

  PodcastSubscription copyWith({
    String? id,
    String? feedUrl,
    String? title,
    String? description,
    String? author,
    Uri? artworkUri,
    DateTime? addedAt,
    DateTime? lastFetchedAt,
    String? lastFetchError,
    bool clearArtworkUri = false,
    bool clearLastFetchedAt = false,
  }) {
    return PodcastSubscription(
      id: id ?? this.id,
      feedUrl: feedUrl ?? this.feedUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      author: author ?? this.author,
      artworkUri: clearArtworkUri ? null : artworkUri ?? this.artworkUri,
      addedAt: addedAt ?? this.addedAt,
      lastFetchedAt:
          clearLastFetchedAt ? null : lastFetchedAt ?? this.lastFetchedAt,
      lastFetchError: lastFetchError ?? this.lastFetchError,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'feedUrl': feedUrl,
      'title': title,
      'description': description,
      'author': author,
      'artworkUri': artworkUri?.toString(),
      'addedAt': addedAt.toIso8601String(),
      'lastFetchedAt': lastFetchedAt?.toIso8601String(),
      'lastFetchError': lastFetchError,
    };
  }

  factory PodcastSubscription.fromJson(Map<String, Object?> json) {
    final feedUrl = json['feedUrl'] as String? ?? '';
    return PodcastSubscription(
      id: json['id'] as String? ?? stablePodcastSubscriptionId(feedUrl),
      feedUrl: feedUrl,
      title: json['title'] as String? ?? 'Untitled podcast',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      artworkUri: _parseUri(json['artworkUri'] as String?),
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastFetchedAt: DateTime.tryParse(json['lastFetchedAt'] as String? ?? ''),
      lastFetchError: json['lastFetchError'] as String? ?? '',
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    return Uri.tryParse(value);
  }
}

const defaultPodcastRefreshInterval = Duration(hours: 12);

String stablePodcastSubscriptionId(String feedUrl) {
  return 'podcast-feed-${Track.stableLocalId(feedUrl.trim())}';
}
