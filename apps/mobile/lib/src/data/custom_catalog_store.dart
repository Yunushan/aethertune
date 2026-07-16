import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/custom_catalog_definition.dart';
import '../domain/music_source_provider.dart';
import 'custom_catalog_provider.dart';

final class CustomCatalogStore extends ChangeNotifier {
  static const _preferencesKey = 'aethertune.custom_catalogs.v1';
  static const maxCatalogs = 20;

  final List<CustomCatalogDefinition> _definitions =
      <CustomCatalogDefinition>[];
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  List<CustomCatalogDefinition> get definitions =>
      List<CustomCatalogDefinition>.unmodifiable(_definitions);

  List<MusicSourceProvider> get musicProviders => <MusicSourceProvider>[
        for (final definition in _definitions) CustomCatalogProvider(definition),
      ];

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferencesKey);
      final decoded = raw == null || raw.isEmpty ? const <Object?>[] : jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Custom catalog storage is invalid.');
      }
      final parsed = <CustomCatalogDefinition>[];
      final ids = <String>{};
      for (final item in decoded.whereType<Map>()) {
        try {
          final definition = CustomCatalogDefinition.fromJson(
            Map<String, Object?>.from(item),
          );
          if (ids.add(definition.id) && parsed.length < maxCatalogs) {
            parsed.add(definition);
          }
        } on Object {
          // One malformed catalog must not disable unaffected user catalogs.
        }
      }
      _definitions
        ..clear()
        ..addAll(parsed);
      _loadError = null;
    } on Object {
      _loadError = 'Custom catalog settings could not be loaded.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(CustomCatalogDefinition definition) async {
    if (!_loaded) {
      await load();
    }
    final index = _definitions.indexWhere((item) => item.id == definition.id);
    if (index < 0 && _definitions.length >= maxCatalogs) {
      throw StateError('AetherTune supports at most $maxCatalogs custom catalogs.');
    }
    if (index < 0) {
      _definitions.add(definition);
    } else {
      _definitions[index] = definition;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final definitionCount = _definitions.length;
    _definitions.removeWhere((definition) => definition.id == id);
    if (_definitions.length == definitionCount) {
      return;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(_definitions.map((definition) => definition.toJson()).toList()),
    );
  }
}
