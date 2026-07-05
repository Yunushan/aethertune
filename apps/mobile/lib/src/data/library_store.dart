import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/track.dart';

class LibraryStore extends ChangeNotifier {
  static const _tracksKey = 'aethertune.tracks.v1';

  final List<Track> _tracks = <Track>[];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get favorites =>
      _tracks.where((track) => track.isFavorite).toList(growable: false);

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tracksKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _tracks
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((item) => Track.fromJson(Map<String, Object?>.from(item)))
              .toList(growable: false),
        );
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> addTracks(List<Track> incoming) async {
    final knownIds = _tracks.map((track) => track.id).toSet();
    var changed = false;

    for (final track in incoming) {
      if (!knownIds.contains(track.id)) {
        _tracks.add(track);
        knownIds.add(track.id);
        changed = true;
      }
    }

    if (changed) {
      _sort();
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeTrack(String id) async {
    _tracks.removeWhere((track) => track.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _tracks.clear();
    await _save();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return;
    }

    final current = _tracks[index];
    _tracks[index] = current.copyWith(isFavorite: !current.isFavorite);
    await _save();
    notifyListeners();
  }

  List<Track> search(String query, {bool favoritesOnly = false}) {
    final normalized = query.trim().toLowerCase();
    final source = favoritesOnly ? favorites : tracks;

    if (normalized.isEmpty) {
      return source;
    }

    return source.where((track) {
      return track.title.toLowerCase().contains(normalized) ||
          track.artist.toLowerCase().contains(normalized) ||
          track.album.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  void _sort() {
    _tracks.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_tracks.map((track) => track.toJson()).toList());
    await prefs.setString(_tracksKey, encoded);
  }
}
