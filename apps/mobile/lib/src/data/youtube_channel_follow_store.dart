import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_data_metadata_provider.dart';

/// A device-local follow list for public YouTube channel metadata.
///
/// This is deliberately separate from YouTube account subscriptions, backups,
/// and sync snapshots. It contains only public display metadata and never a
/// Google credential, remote feed, or playback state.
final class YouTubeChannelFollowStore extends ChangeNotifier {
  static const _preferencesKey = 'aethertune.youtube_channel_follows.v1';

  final List<YouTubeChannelFollow> _follows = <YouTubeChannelFollow>[];
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  List<YouTubeChannelFollow> get follows =>
      List<YouTubeChannelFollow>.unmodifiable(_follows);

  bool isFollowed(String channelId) {
    final normalizedId = channelId.trim();
    return normalizedId.isNotEmpty &&
        _follows.any((follow) => follow.id == normalizedId);
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferencesKey);
      final decoded = raw == null || raw.isEmpty
          ? const <Object?>[]
          : jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('YouTube channel follow storage is invalid.');
      }
      final parsed = <YouTubeChannelFollow>[];
      final ids = <String>{};
      for (final item in decoded.whereType<Map>()) {
        final follow = YouTubeChannelFollow.tryFromJson(
          Map<String, Object?>.from(item),
        );
        if (follow != null && ids.add(follow.id)) {
          parsed.add(follow);
        }
      }
      parsed.sort((a, b) => _compareText(a.title, b.title));
      _follows
        ..clear()
        ..addAll(parsed);
      _loadError = null;
    } on Object {
      _loadError = 'YouTube channel follows could not be loaded.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<bool> setFollowed(YouTubeDataChannel channel, bool followed) async {
    if (!_loaded) {
      await load();
    }
    final id = channel.id.trim();
    final title = channel.title.trim();
    if (id.isEmpty || title.isEmpty) {
      return false;
    }
    final index = _follows.indexWhere((follow) => follow.id == id);
    if (followed) {
      final replacement = YouTubeChannelFollow.fromChannel(channel);
      if (index >= 0) {
        if (_follows[index] == replacement) {
          return false;
        }
        _follows[index] = replacement;
      } else {
        _follows.add(replacement);
      }
      _follows.sort((a, b) => _compareText(a.title, b.title));
    } else {
      if (index < 0) {
        return false;
      }
      _follows.removeAt(index);
    }
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(_follows.map((follow) => follow.toJson()).toList()),
    );
  }
}

final class YouTubeChannelFollow {
  const YouTubeChannelFollow({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUri,
  });

  factory YouTubeChannelFollow.fromChannel(YouTubeDataChannel channel) {
    return YouTubeChannelFollow(
      id: channel.id.trim(),
      title: channel.title.trim(),
      description: _nonEmpty(channel.description),
      thumbnailUri: _httpsUri(channel.thumbnailUri),
    );
  }

  final String id;
  final String title;
  final String? description;
  final Uri? thumbnailUri;

  static YouTubeChannelFollow? tryFromJson(Map<String, Object?> json) {
    final id = _nonEmpty(json['id']?.toString());
    final title = _nonEmpty(json['title']?.toString());
    if (id == null || title == null) {
      return null;
    }
    final thumbnail = _httpsUri(
      Uri.tryParse(json['thumbnailUri']?.toString() ?? ''),
    );
    return YouTubeChannelFollow(
      id: id,
      title: title,
      description: _nonEmpty(json['description']?.toString()),
      thumbnailUri: thumbnail,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    if (thumbnailUri != null) 'thumbnailUri': thumbnailUri.toString(),
  };

  @override
  bool operator ==(Object other) =>
      other is YouTubeChannelFollow &&
      id == other.id &&
      title == other.title &&
      description == other.description &&
      thumbnailUri == other.thumbnailUri;

  @override
  int get hashCode => Object.hash(id, title, description, thumbnailUri);
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

Uri? _httpsUri(Uri? value) =>
    value != null && value.scheme == 'https' && value.host.isNotEmpty
    ? value
    : null;

int _compareText(String first, String second) =>
    first.toLowerCase().compareTo(second.toLowerCase());
