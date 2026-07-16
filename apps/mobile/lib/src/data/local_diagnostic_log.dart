import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retains a small, user-exportable local diagnostic history.
///
/// This is intentionally not a crash-reporting SDK: entries never leave the
/// device unless a user explicitly exports the JSON document from Options.
class LocalDiagnosticLog extends ChangeNotifier {
  LocalDiagnosticLog({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const storageKey = 'aethertune.local_diagnostic_log.v1';
  static const maximumEntries = 40;
  static const _maximumMessageCharacters = 900;
  static const _maximumStackCharacters = 3200;

  final DateTime Function() _clock;
  final List<LocalDiagnosticEntry> _entries = <LocalDiagnosticEntry>[];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<LocalDiagnosticEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded) {
            if (value is Map) {
              final entry = LocalDiagnosticEntry.fromJson(
                Map<String, Object?>.from(value),
              );
              if (entry != null) {
                _entries.add(entry);
              }
            }
          }
          _entries.sort(
            (left, right) => right.recordedAt.compareTo(left.recordedAt),
          );
          if (_entries.length > maximumEntries) {
            _entries.removeRange(maximumEntries, _entries.length);
          }
        }
      } on Object {
        await prefs.remove(storageKey);
        _entries.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> record(
    Object error, {
    StackTrace? stackTrace,
    required String origin,
  }) async {
    final normalizedOrigin = origin.trim().isEmpty ? 'unknown' : origin.trim();
    final entry = LocalDiagnosticEntry(
      recordedAt: _clock().toUtc(),
      origin: _truncate(normalizedOrigin, 80),
      message: _sanitize(error.toString(), _maximumMessageCharacters),
      stackTrace: _sanitize(
        stackTrace?.toString() ?? '',
        _maximumStackCharacters,
      ),
    );
    _entries.insert(0, entry);
    if (_entries.length > maximumEntries) {
      _entries.removeRange(maximumEntries, _entries.length);
    }
    _loaded = true;
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    notifyListeners();
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': 'aethertune-local-diagnostics',
      'version': 1,
      'entries': _entries.map((entry) => entry.toJson()).toList(growable: false),
      'privacy': 'Stored locally. Exported only by an explicit user action.',
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(
        _entries.map((entry) => entry.toJson()).toList(growable: false),
      ),
    );
  }
}

class LocalDiagnosticEntry {
  const LocalDiagnosticEntry({
    required this.recordedAt,
    required this.origin,
    required this.message,
    required this.stackTrace,
  });

  final DateTime recordedAt;
  final String origin;
  final String message;
  final String stackTrace;

  Map<String, Object?> toJson() => <String, Object?>{
    'recordedAt': recordedAt.toIso8601String(),
    'origin': origin,
    'message': message,
    'stackTrace': stackTrace,
  };

  static LocalDiagnosticEntry? fromJson(Map<String, Object?> json) {
    final recordedAt = DateTime.tryParse(json['recordedAt'] as String? ?? '');
    final origin = json['origin'] as String?;
    final message = json['message'] as String?;
    final stackTrace = json['stackTrace'] as String?;
    if (recordedAt == null ||
        origin == null ||
        message == null ||
        stackTrace == null) {
      return null;
    }
    return LocalDiagnosticEntry(
      recordedAt: recordedAt.toUtc(),
      origin: origin,
      message: message,
      stackTrace: stackTrace,
    );
  }
}

String _sanitize(String value, int maximumLength) {
  var sanitized = value.trim();
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(?im)\bauthorization\s*[:=].*$'),
    (_) => 'authorization=[redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'(?i)\b(authorization|token|password|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+',
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  sanitized = sanitized.replaceAll(RegExp(r'(?i)file://\S+'), 'file://[redacted]');
  sanitized = sanitized.replaceAll(
    RegExp(r'(?i)(https?://)[^\s/@]+@'),
    r'$1[redacted]@',
  );
  return _truncate(sanitized, maximumLength);
}

String _truncate(String value, int maximumLength) {
  if (value.length <= maximumLength) {
    return value;
  }
  return '${value.substring(0, maximumLength)}... [truncated]';
}
