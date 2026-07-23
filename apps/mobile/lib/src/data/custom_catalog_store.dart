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

    if (!_loaded) {
      await load();
    }
    final existingIds = _definitions.map((definition) => definition.id).toSet();
    final imports = candidates
        .where((definition) => !existingIds.contains(definition.id))
        .toList(growable: false);
    if (_definitions.length + imports.length > maxCatalogs) {
      throw StateError('AetherTune supports at most $maxCatalogs custom catalogs.');
    }
    final result = CustomCatalogConfigurationImportResult(
      importedCatalogCount: imports.length,
      skippedExistingCatalogCount: candidates.length - imports.length,
      skippedInsecureCatalogCount: skippedInsecureCatalogCount,
    );
    if (imports.isEmpty) {
      return result;
    }
    final previous = List<CustomCatalogDefinition>.from(_definitions);
    try {
      _definitions
        ..addAll(imports)
        ..sort((left, right) => left.name.compareTo(right.name));
      await _persist();
    } on Object {
      _definitions
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    notifyListeners();
    return result;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(_definitions.map((definition) => definition.toJson()).toList()),
    );
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
