import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/track.dart';
import 'youtube_channel_follow_store.dart';
import 'youtube_data_metadata_provider.dart';
import 'youtube_followed_channel_feed.dart';

/// A device-local cache of explicitly refreshed public channel metadata.
///
/// It is deliberately not a YouTube account subscription service, sync data,
/// or media cache. Every item is reduced to safe public display metadata and
/// contains no stream URL, local path, credential, or user-library state.
final class YouTubeFollowedChannelFeedStore extends ChangeNotifier {
  static const _preferencesKey = 'aethertune.youtube_followed_feed.v1';
  static const _documentVersion = 1;
  static const _maxItems = 100;

  final List<YouTubeFollowedChannelFeedItem> _items =
      <YouTubeFollowedChannelFeedItem>[];
  bool _loaded = false;
  bool _refreshing = false;
  String? _loadError;
  DateTime? _lastRefreshedAt;
  int _lastFailedChannelCount = 0;

  bool get loaded => _loaded;
  bool get refreshing => _refreshing;
  String? get loadError => _loadError;
  DateTime? get lastRefreshedAt => _lastRefreshedAt;
  int get lastFailedChannelCount => _lastFailedChannelCount;
  List<YouTubeFollowedChannelFeedItem> get items =>
      List<YouTubeFollowedChannelFeedItem>.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _preferencesKey,
      );
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('Followed-channel cache is invalid.');
        }
        final document = Map<String, Object?>.from(decoded);
        if (document['version'] != _documentVersion ||
            document['items'] is! List) {
          throw const FormatException('Followed-channel cache is invalid.');
        }
        final parsed = <YouTubeFollowedChannelFeedItem>[];
        final ids = <String>{};
        for (final rawItem in (document['items'] as List).take(_maxItems)) {
          if (rawItem is! Map) {
            continue;
          }
          final item = _itemFromJson(Map<String, Object?>.from(rawItem));
          if (item != null && ids.add(item.track.id)) {
            parsed.add(item);
          }
        }
        parsed.sort(_compareItems);
        _items
          ..clear()
          ..addAll(parsed);
        _lastRefreshedAt = DateTime.tryParse(
          document['lastRefreshedAt']?.toString() ?? '',
        )?.toUtc();
        _lastFailedChannelCount =
            (document['lastFailedChannelCount'] as num?)?.toInt() ?? 0;
      }
      _loadError = null;
    } on Object {
      _loadError = 'Followed-channel metadata could not be loaded.';
    }
    _loaded = true;
    notifyListeners();
  }

  /// Refreshes using the official metadata adapter only after an explicit UI
  /// action. Successful results replace stale cache entries; an all-failure
  /// refresh retains the last usable public metadata.
  Future<YouTubeFollowedChannelFeed?> refresh(
    YouTubeDataMetadataProvider provider,
    Iterable<YouTubeChannelFollow> follows, {
    int limitPerChannel = 5,
    int? maxChannels,
  }) async {
    if (!_loaded) {
      await load();
    }
    if (_refreshing) {
      return null;
    }
    _refreshing = true;
    notifyListeners();
    try {
      final feed = await loadYouTubeFollowedChannelFeed(
        provider,
        follows,
        limitPerChannel: limitPerChannel,
        maxChannels: maxChannels,
      );
      if (feed.items.isNotEmpty || feed.failedChannelCount == 0) {
        _items
          ..clear()
          ..addAll(
            feed.items
                .map(_sanitizeItem)
                .take(_maxItems),
          )
          ..sort(_compareItems);
      }
      _lastRefreshedAt = DateTime.now().toUtc();
      _lastFailedChannelCount = feed.failedChannelCount;
      await _persist();
      return feed;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final document = <String, Object?>{
      'version': _documentVersion,
      'lastRefreshedAt': _lastRefreshedAt?.toIso8601String(),
      'lastFailedChannelCount': _lastFailedChannelCount,
      'items': _items.map(_itemToJson).toList(growable: false),
    };
    await (await SharedPreferences.getInstance()).setString(
      _preferencesKey,
      jsonEncode(document),
    );
  }
}

YouTubeFollowedChannelFeedItem _sanitizeItem(
  YouTubeFollowedChannelFeedItem item,
) {
  final publishedAt = item.publishedAt?.toUtc();
  final track = item.track;
  return YouTubeFollowedChannelFeedItem(
    track: Track(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      artworkUri: _safeWebUri(track.artworkUri),
      sourceId: 'youtube-data-metadata',
      externalId: track.externalId,
      addedAt: publishedAt ?? track.addedAt,
    ),
    channelTitle: item.channelTitle.trim(),
    publishedAt: publishedAt,
  );
}

Map<String, Object?> _itemToJson(YouTubeFollowedChannelFeedItem item) =>
    <String, Object?>{
      'track': item.track.toJson(),
      'channelTitle': item.channelTitle,
      if (item.publishedAt != null)
        'publishedAt': item.publishedAt!.toIso8601String(),
    };

YouTubeFollowedChannelFeedItem? _itemFromJson(Map<String, Object?> json) {
  final rawTrack = json['track'];
  final channelTitle = json['channelTitle']?.toString().trim() ?? '';
  if (rawTrack is! Map || channelTitle.isEmpty) {
    return null;
  }
  try {
    final stored = Track.fromJson(Map<String, Object?>.from(rawTrack));
    if (stored.id.trim().isEmpty ||
        stored.sourceId != 'youtube-data-metadata') {
      return null;
    }
    return _sanitizeItem(
      YouTubeFollowedChannelFeedItem(
        track: stored,
        channelTitle: channelTitle,
        publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      ),
    );
  } on Object {
    return null;
  }
}

Uri? _safeWebUri(Uri? uri) =>
    uri != null && uri.host.isNotEmpty && uri.scheme == 'https' ? uri : null;

int _compareItems(
  YouTubeFollowedChannelFeedItem first,
  YouTubeFollowedChannelFeedItem second,
) {
  final firstTime = first.publishedAt;
  final secondTime = second.publishedAt;
  if (firstTime == null && secondTime == null) {
    return first.track.title.toLowerCase().compareTo(
      second.track.title.toLowerCase(),
    );
  }
  if (firstTime == null) {
    return 1;
  }
  if (secondTime == null) {
    return -1;
  }
  final byTime = secondTime.compareTo(firstTime);
  return byTime != 0
      ? byTime
      : first.track.title.toLowerCase().compareTo(second.track.title.toLowerCase());
}
