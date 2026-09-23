import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/custom_catalog_definition.dart';
import '../domain/music_source_provider.dart';
import 'custom_catalog_provider.dart';

final class CustomCatalogStore extends ChangeNotifier {
  static const _preferencesKey = 'aethertune.custom_catalogs.v1';
  static const maxCatalogs = 20;
  static const configurationDocumentFormat = 'aethertune.custom_catalogs';
  static const configurationDocumentVersion = 1;
  static const _maximumConfigurationBytes = 64 * 1024;

  /// Only HTTPS definitions can leave the device. Local HTTP consent is not
  /// portable because another network may route the hostname differently.
  CustomCatalogConfigurationExport exportConfiguration() {
    final exportable = _definitions
        .where((definition) => definition.catalogUri.scheme == 'https')
        .toList(growable: false);
    return CustomCatalogConfigurationExport(
      json: jsonEncode(<String, Object?>{
        'format': configurationDocumentFormat,
        'version': configurationDocumentVersion,
        'catalogs': exportable
            .map((definition) => definition.toJson())
            .toList(growable: false),
      }),
      exportedCatalogCount: exportable.length,
      skippedInsecureCatalogCount: _definitions.length - exportable.length,
    );
  }

  final List<CustomCatalogDefinition> _definitions =
      <CustomCatalogDefinition>[];
  bool _loaded = false;
  String? _loadError;
  Future<void>? _loadFuture;
  Future<void> _mutationTail = Future<void>.value();

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  List<CustomCatalogDefinition> get definitions =>
      List<CustomCatalogDefinition>.unmodifiable(_definitions);

  List<MusicSourceProvider> get musicProviders => <MusicSourceProvider>[
    for (final definition in _definitions) CustomCatalogProvider(definition),
  ];

  Future<void> load() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferencesKey);
      final decoded = raw == null || raw.isEmpty
          ? const <Object?>[]
          : jsonDecode(raw);
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

  Future<void> save(CustomCatalogDefinition definition) => _serialize(() async {
    await load();
    _requireLoadedStorage();
    final next = List<CustomCatalogDefinition>.from(_definitions);
    final index = next.indexWhere((item) => item.id == definition.id);
    if (index < 0 && next.length >= maxCatalogs) {
      throw StateError(
        'AetherTune supports at most $maxCatalogs custom catalogs.',
      );
    }
    if (index < 0) {
      next.add(definition);
    } else {
      next[index] = definition;
    }
    await _persist(next);
    _definitions
      ..clear()
      ..addAll(next);
    notifyListeners();
  });

  Future<void> remove(String id) => _serialize(() async {
    await load();
    _requireLoadedStorage();
    final next = List<CustomCatalogDefinition>.from(_definitions)
      ..removeWhere((definition) => definition.id == id);
    if (next.length == _definitions.length) {
      return;
    }
    await _persist(next);
    _definitions
      ..clear()
      ..addAll(next);
    notifyListeners();
  });

  Future<CustomCatalogConfigurationImportResult> importConfiguration(
    String document,
  ) async {
    if (utf8.encode(document).length > _maximumConfigurationBytes) {
      throw const FormatException('Custom catalog configuration is too large.');
    }
    final decoded = jsonDecode(document);
    if (decoded is! Map) {
      throw const FormatException('Custom catalog configuration is invalid.');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['format'] != configurationDocumentFormat ||
        root['version'] != configurationDocumentVersion) {
      throw const FormatException(
        'This is not a supported custom catalog configuration.',
      );
    }
    final rawCatalogs = root['catalogs'];
    if (rawCatalogs is! List || rawCatalogs.length > maxCatalogs) {
      throw const FormatException(
        'Custom catalog configuration has an invalid catalog list.',
      );
    }

    final candidates = <CustomCatalogDefinition>[];
    final documentIds = <String>{};
    var skippedInsecureCatalogCount = 0;
    for (final rawCatalog in rawCatalogs) {
      if (rawCatalog is! Map) {
        throw const FormatException(
          'Custom catalog configuration contains an invalid catalog.',
        );
      }
      final definition = CustomCatalogDefinition.fromJson(
        Map<String, Object?>.from(rawCatalog),
      );
      if (!documentIds.add(definition.id)) {
        throw const FormatException(
          'Custom catalog configuration contains duplicate catalogs.',
        );
      }
      if (definition.catalogUri.scheme != 'https') {
        skippedInsecureCatalogCount += 1;
        continue;
      }
      candidates.add(definition);
    }

    return _serialize(() async {
      await load();
      _requireLoadedStorage();
      final existingIds = _definitions
          .map((definition) => definition.id)
          .toSet();
      final imports = candidates
          .where((definition) => !existingIds.contains(definition.id))
          .toList(growable: false);
      if (_definitions.length + imports.length > maxCatalogs) {
        throw StateError(
          'AetherTune supports at most $maxCatalogs custom catalogs.',
        );
      }
      final result = CustomCatalogConfigurationImportResult(
        importedCatalogCount: imports.length,
        skippedExistingCatalogCount: candidates.length - imports.length,
        skippedInsecureCatalogCount: skippedInsecureCatalogCount,
      );
      if (imports.isEmpty) {
        return result;
      }
      final next = List<CustomCatalogDefinition>.from(_definitions)
        ..addAll(imports)
        ..sort((left, right) => left.name.compareTo(right.name));
      await _persist(next);
      _definitions
        ..clear()
        ..addAll(next);
      notifyListeners();
      return result;
    });
  }

  void _requireLoadedStorage() {
    if (_loadError != null) {
      throw StateError(
        'Custom catalog settings could not be loaded. Resolve the storage error before editing catalogs.',
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _persist(List<CustomCatalogDefinition> definitions) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = await prefs.setString(
        _preferencesKey,
        jsonEncode(
          definitions.map((definition) => definition.toJson()).toList(),
        ),
      );
      if (!saved) {
        throw StateError('Custom catalog settings could not be saved.');
      }
    } on Object {
      // SharedPreferences changes its local cache before the platform write.
      // Reload it so a rejected write cannot appear durable to another store.
      try {
        await prefs.reload();
      } on Object {
        // Preserve the original write failure for the caller.
      }
      rethrow;
    }
  }
}

final class CustomCatalogConfigurationExport {
  const CustomCatalogConfigurationExport({
    required this.json,
    required this.exportedCatalogCount,
    required this.skippedInsecureCatalogCount,
  });

  final String json;
  final int exportedCatalogCount;
  final int skippedInsecureCatalogCount;
}

final class CustomCatalogConfigurationImportResult {
  const CustomCatalogConfigurationImportResult({
    required this.importedCatalogCount,
    required this.skippedExistingCatalogCount,
    required this.skippedInsecureCatalogCount,
  });

  final int importedCatalogCount;
  final int skippedExistingCatalogCount;
  final int skippedInsecureCatalogCount;
}
