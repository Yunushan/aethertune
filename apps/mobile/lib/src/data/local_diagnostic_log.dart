import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bounded, best-effort local diagnostics; never captures raw error payloads.
class LocalDiagnosticLog extends ChangeNotifier {
  LocalDiagnosticLog({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const storageKey = 'aethertune.local_diagnostic_log.v2';
  static const legacyStorageKey = 'aethertune.local_diagnostic_log.v1';
  static const maximumEntries = 40;
  static const maximumPendingRecords = 40;
  static const maximumStoredCharacters = 256 * 1024;

  final DateTime Function() _clock;
  final List<LocalDiagnosticEntry> _entries = [];
  Future<void> _tail = Future<void>.value();
  bool _loaded = false;
  bool _persistenceError = false;
  bool _disposed = false;
  int _pendingRecords = 0;
  int _discardedReports = 0;

  bool get loaded => _loaded;
  bool get persistenceError => _persistenceError;
  List<LocalDiagnosticEntry> get entries => List.unmodifiable(_entries);

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _serialized(_load);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.get(storageKey);
      if (raw is String && raw.length <= maximumStoredCharacters) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['version'] == 2) {
          final discarded = _safeCode(decoded['discardedReports']);
          if (discarded != null && discarded > 0) {
            _discardedReports += discarded;
            if (_discardedReports > 2147483647) _discardedReports = 2147483647;
          }
          final entries = decoded['entries'];
          if (entries is List) {
            for (final value in entries.take(maximumEntries)) {
              if (value is! Map) continue;
              final entry = LocalDiagnosticEntry.fromJson(value);
              if (entry != null) _entries.add(entry);
            }
          }
        }
      }
    } on Object {
      // Diagnostics must not prevent app startup or recursively log failures.
      _persistenceError = true;
    }
    _loaded = true;
    _trim();
    await _persist();
    _notify();
  }

  Future<void> record(
    Object error, {
    StackTrace? stackTrace,
    required String origin,
  }) {
    if (_disposed) return Future<void>.value();
    if (_pendingRecords >= maximumPendingRecords) {
      if (_discardedReports < 2147483647) _discardedReports++;
      return Future<void>.value();
    }
    final entry = LocalDiagnosticEntry._(
      recordedAt: _clock().toUtc(),
      origin: _safeOrigin(origin),
      category: _category(error),
      code: _errorCode(error),
      frames: _frames(stackTrace),
    );
    _pendingRecords++;
    return _serialized(() async {
      await _load();
      _entries.insert(0, entry);
      _trim();
      await _persist();
      _notify();
    }).whenComplete(() => _pendingRecords--);
  }

  void _trim() {
    _entries.sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    if (_entries.length > maximumEntries) {
      _entries.removeRange(maximumEntries, _entries.length);
    }
  }

  Future<bool> clear() => _serialized(() async {
    _entries.clear();
    _discardedReports = 0;
    _loaded = true;
    _persistenceError = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentRemoved = await prefs.remove(storageKey);
      final legacyRemoved = await prefs.remove(legacyStorageKey);
      await prefs.reload();
      _persistenceError =
          !currentRemoved ||
          !legacyRemoved ||
          prefs.containsKey(storageKey) ||
          prefs.containsKey(legacyStorageKey);
    } on Object {
      _persistenceError = true;
    }
    _notify();
    return !_persistenceError;
  });

  Map<String, Object?> _document() => {
    'format': 'aethertune-local-diagnostics',
    'version': 2,
    'discardedReports': _discardedReports,
    'entries': _entries.map((entry) => entry.toJson()).toList(growable: false),
    'privacy':
        'Stored locally. Exported only by an explicit user action. '
        'Raw error text, network URLs, local file paths, and bodies are omitted.',
  };

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(_document());

  Future<void> _persist() async {
    _persistenceError = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Legacy free-form reports may contain credentials; never load/export them.
      final legacyRemoved = await prefs.remove(legacyStorageKey);
      final encoded = jsonEncode(_document());
      final saved = await prefs.setString(storageKey, encoded);
      await prefs.reload();
      _persistenceError =
          !legacyRemoved ||
          !saved ||
          prefs.containsKey(legacyStorageKey) ||
          prefs.get(storageKey) != encoded;
    } on Object {
      _persistenceError = true;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum LocalDiagnosticCategory {
  framework('Flutter framework error'),
  platform('Platform operation failed'),
  missingPlugin('Platform plugin unavailable'),
  network('Network connection failed'),
  http('HTTP operation failed'),
  timeout('Operation timed out'),
  filesystem('Filesystem operation failed'),
  format('Invalid data format'),
  argument('Invalid argument'),
  state('Invalid application state'),
  type('Unexpected value type'),
  unsupported('Unsupported operation'),
  assertion('Assertion failed'),
  exception('Operation failed'),
  unknown('Unexpected error');

  const LocalDiagnosticCategory(this.message);
  final String message;
}

final class LocalDiagnosticEntry {
  LocalDiagnosticEntry._({
    required this.recordedAt,
    required this.origin,
    required this.category,
    required this.code,
    required List<LocalDiagnosticFrame> frames,
  }) : frames = List.unmodifiable(frames);

  final DateTime recordedAt;
  final String origin;
  final LocalDiagnosticCategory category;
  final int? code;
  final List<LocalDiagnosticFrame> frames;
  String get message => category.message;

  Map<String, Object?> toJson() => {
    'recordedAt': recordedAt.toIso8601String(),
    'origin': origin,
    'category': category.name,
    'message': message,
    if (code != null) 'code': code,
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  };

  static LocalDiagnosticEntry? fromJson(Map<Object?, Object?> json) {
    final date = json['recordedAt'];
    if (date is! String || date.length > 40) return null;
    final recordedAt = DateTime.tryParse(date);
    if (recordedAt == null) return null;
    var category = LocalDiagnosticCategory.unknown;
    for (final candidate in LocalDiagnosticCategory.values) {
      if (json['category'] == candidate.name) category = candidate;
    }
    final rawFrames = json['frames'];
    return LocalDiagnosticEntry._(
      recordedAt: recordedAt.toUtc(),
      origin: _safeOrigin(json['origin']),
      category: category,
      code: _safeCode(json['code']),
      frames: [
        if (rawFrames is List)
          for (final frame in rawFrames.take(_maximumFrames))
            if (frame is Map) ?LocalDiagnosticFrame.fromJson(frame),
      ],
    );
  }
}

final class LocalDiagnosticFrame {
  const LocalDiagnosticFrame._(this.uri, this.line, this.column);
  final String uri;
  final int line;
  final int column;

  Map<String, Object?> toJson() => {'uri': uri, 'line': line, 'column': column};

  static LocalDiagnosticFrame? fromJson(Map<Object?, Object?> json) {
    final source = json['uri'];
    final line = _safeCode(json['line']);
    final column = _safeCode(json['column']);
    if (source is! String ||
        source.length > 180 ||
        line == null ||
        line < 0 ||
        column == null ||
        column < 0) {
      return null;
    }
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !{'package', 'dart'}.contains(uri.scheme) ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(
          r'^[a-z][a-z0-9_]*/[A-Za-z0-9_./-]+\.dart$',
        ).hasMatch(uri.path) ||
        uri.pathSegments.any(
          (part) => part.isEmpty || part == '.' || part == '..',
        ) ||
        source.contains('%')) {
      return null;
    }
    return LocalDiagnosticFrame._(uri.toString(), line, column);
  }
}

String _safeOrigin(Object? origin) => switch (origin) {
  'flutter' => 'flutter',
  'platform-dispatcher' => 'platform-dispatcher',
  _ => 'unknown',
};

LocalDiagnosticCategory _category(Object error) => switch (error) {
  FlutterError() => LocalDiagnosticCategory.framework,
  PlatformException() => LocalDiagnosticCategory.platform,
  MissingPluginException() => LocalDiagnosticCategory.missingPlugin,
  SocketException() => LocalDiagnosticCategory.network,
  HttpException() => LocalDiagnosticCategory.http,
  TimeoutException() => LocalDiagnosticCategory.timeout,
  FileSystemException() => LocalDiagnosticCategory.filesystem,
  FormatException() => LocalDiagnosticCategory.format,
  ArgumentError() => LocalDiagnosticCategory.argument,
  StateError() => LocalDiagnosticCategory.state,
  TypeError() => LocalDiagnosticCategory.type,
  UnsupportedError() => LocalDiagnosticCategory.unsupported,
  AssertionError() => LocalDiagnosticCategory.assertion,
  Exception() => LocalDiagnosticCategory.exception,
  _ => LocalDiagnosticCategory.unknown,
};

int? _safeCode(Object? code) =>
    code is int && code >= -2147483648 && code <= 2147483647 ? code : null;

int? _errorCode(Object error) => _safeCode(switch (error) {
  FileSystemException(:final osError) => osError?.errorCode,
  SocketException(:final osError) => osError?.errorCode,
  PlatformException(:final code) when code.length <= 11 => int.tryParse(code),
  _ => null,
});

const _maximumFrames = 12;

List<LocalDiagnosticFrame> _frames(StackTrace? stack) {
  if (stack == null) return [];
  final frames = <LocalDiagnosticFrame>[];
  try {
    final raw = stack.toString();
    final bounded = raw.length <= 16384 ? raw : raw.substring(0, 16384);
    for (final source in const LineSplitter().convert(bounded).take(80)) {
      if (source.length > 1024) continue;
      try {
        final parsed = StackFrame.fromStackTraceLine(source);
        if (parsed == null) continue;
        final frame = LocalDiagnosticFrame.fromJson({
          'uri': [
            parsed.packageScheme,
            ':',
            parsed.package,
            '/',
            parsed.packagePath,
          ].join(),
          'line': parsed.line,
          'column': parsed.column,
        });
        if (frame != null) frames.add(frame);
        if (frames.length == _maximumFrames) break;
      } on Object {
        // Unknown native/web formats are omitted, not stored as raw text.
      }
    }
  } on Object {
    // A failing custom StackTrace.toString must not fail error capture itself.
  }
  return frames;
}
