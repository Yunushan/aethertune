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
  static const _documentVersion = 1;
  static const _maxFollows = 500;
  static const _maxDocumentBytes = 512 * 1024;

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

  /// Adds valid public channel metadata in one durable device-local update.
  ///
  /// This never imports an account identity, credential, or remote feed.
  Future<int> followAll(Iterable<YouTubeDataChannel> channels) async {
    if (!_loaded) {
      await load();
    }
    final next = <String, YouTubeChannelFollow>{
      for (final follow in _follows) follow.id: follow,
    };
    var changed = 0;
    for (final channel in channels) {
      final follow = YouTubeChannelFollow.fromChannel(channel);
      if (follow.id.isEmpty || follow.title.isEmpty) {
        continue;
      }
      if (next[follow.id] != follow) {
        next[follow.id] = follow;
        changed += 1;
      }
    }
    if (changed == 0) {
      return 0;
    }
    _follows
      ..clear()
      ..addAll(next.values)
      ..sort((a, b) => _compareText(a.title, b.title));
    await _persist();
    notifyListeners();
    return changed;
  }

  /// Exports only device-local public channel metadata for explicit transfer.
  ///
  /// The document intentionally omits Google credentials, YouTube account
  /// subscriptions, remote-feed results, and playback state.
  String exportFollowDocument() => jsonEncode(<String, Object?>{
        'version': _documentVersion,
        'follows': _follows.map((follow) => follow.toJson()).toList(),
      });

  /// Imports a bounded public-channel follow document.
  ///
  /// Imports merge by channel ID by default, refreshing public display data.
  /// [replace] is reserved for an explicit user choice in the caller.
  Future<int> importFollowDocument(
    String document, {
    bool replace = false,
  }) async {
    if (!_loaded) {
      await load();
    }
    if (utf8.encode(document).length > _maxDocumentBytes) {
      throw const FormatException('Follow document is too large.');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(document);
    } on FormatException {
      throw const FormatException('Follow document is not valid JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Follow document must be an object.');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['version'] != _documentVersion) {
      throw const FormatException('Unsupported follow document version.');
    }
    final rawFollows = root['follows'];
    if (rawFollows is! List || rawFollows.length > _maxFollows) {
      throw const FormatException('Follow document contains too many channels.');
    }

    final incoming = <YouTubeChannelFollow>[];
    final incomingIds = <String>{};
    for (final rawFollow in rawFollows) {
      if (rawFollow is! Map) {
        throw const FormatException('Follow document contains an invalid channel.');
      }
      final follow = YouTubeChannelFollow.tryFromJson(
        Map<String, Object?>.from(rawFollow),
      );
      if (follow == null) {
        throw const FormatException('Follow document contains an invalid channel.');
      }
      if (incomingIds.add(follow.id)) {
        incoming.add(follow);
      }
    }

    final previous = <String, YouTubeChannelFollow>{
      for (final follow in _follows) follow.id: follow,
    };
    final merged = replace
        ? <String, YouTubeChannelFollow>{
            for (final follow in incoming) follow.id: follow,
          }
        : <String, YouTubeChannelFollow>{
            ...previous,
            for (final follow in incoming) follow.id: follow,
          };
    final next = merged.values.toList()
      ..sort((a, b) => _compareText(a.title, b.title));
    final changed = _followDifferenceCount(previous, next);
    if (changed == 0) {
      return 0;
    }

    _follows
      ..clear()
      ..addAll(next);
    await _persist();
    notifyListeners();
    return changed;
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

int _followDifferenceCount(
  Map<String, YouTubeChannelFollow> previous,
  List<YouTubeChannelFollow> next,
) {
  final nextById = <String, YouTubeChannelFollow>{
    for (final follow in next) follow.id: follow,
  };
  var changed = 0;
  for (final follow in next) {
    if (previous[follow.id] != follow) {
      changed += 1;
    }
  }
  for (final id in previous.keys) {
    if (!nextById.containsKey(id)) {
      changed += 1;
    }
  }
  return changed;
}
