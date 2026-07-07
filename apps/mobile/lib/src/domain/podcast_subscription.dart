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
  }) : addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String feedUrl;
  final String title;
  final String description;
  final String author;
  final Uri? artworkUri;
  final DateTime addedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'feedUrl': feedUrl,
      'title': title,
      'description': description,
      'author': author,
      'artworkUri': artworkUri?.toString(),
      'addedAt': addedAt.toIso8601String(),
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
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    return Uri.tryParse(value);
  }
}

String stablePodcastSubscriptionId(String feedUrl) {
  return 'podcast-feed-${Track.stableLocalId(feedUrl.trim())}';
}
