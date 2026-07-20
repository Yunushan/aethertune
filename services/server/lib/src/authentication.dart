import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

abstract interface class SyncAuthenticator {
  bool get isConfigured;

  String? authenticate(String token);
}

abstract interface class OperationsAuthenticator {
  bool get isConfigured;

  bool authenticate(String token);
}

class DisabledOperationsAuthenticator implements OperationsAuthenticator {
  const DisabledOperationsAuthenticator();

  @override
  bool get isConfigured => false;

  @override
  bool authenticate(String token) => false;
}

class StaticOperationsAuthenticator implements OperationsAuthenticator {
  StaticOperationsAuthenticator(String configuredToken)
      : _tokenHash = _configuredTokenHash(
          configuredToken,
          configurationName: 'AETHERTUNE_OPS_TOKEN',
        );

  final List<int> _tokenHash;

  @override
  bool get isConfigured => true;

  @override
  bool authenticate(String token) {
    return _constantTimeEquals(
      sha256.convert(utf8.encode(token)).bytes,
      _tokenHash,
    );
  }
}

class DisabledSyncAuthenticator implements SyncAuthenticator {
  const DisabledSyncAuthenticator();

  @override
  bool get isConfigured => false;

  @override
  String? authenticate(String token) => null;
}

class CompositeSyncAuthenticator implements SyncAuthenticator {
  CompositeSyncAuthenticator(Iterable<SyncAuthenticator> authenticators)
      : _authenticators = List<SyncAuthenticator>.unmodifiable(authenticators);

  final List<SyncAuthenticator> _authenticators;

  @override
  bool get isConfigured =>
      _authenticators.any((authenticator) => authenticator.isConfigured);

  @override
  String? authenticate(String token) {
    for (final authenticator in _authenticators) {
      final accountId = authenticator.authenticate(token);
      if (accountId != null) {
        return accountId;
      }
    }
    return null;
  }
}

class StaticSyncAuthenticator implements SyncAuthenticator {
  StaticSyncAuthenticator(Map<String, String> users)
      : _credentials = _validatedStaticCredentials(
          _credentialsFromFlatMap(users),
        );

  StaticSyncAuthenticator._(List<_StaticSyncCredential> credentials)
      : _credentials = _validatedStaticCredentials(credentials);

  factory StaticSyncAuthenticator.fromJson(String? rawUsers) {
    if (rawUsers == null || rawUsers.trim().isEmpty) {
      return StaticSyncAuthenticator(const <String, String>{});
    }
    final decoded = jsonDecode(rawUsers);
    if (decoded is! Map) {
      throw const FormatException(
        'AETHERTUNE_SYNC_USERS must be a JSON object.',
      );
    }
    return StaticSyncAuthenticator._(_credentialsFromJsonMap(decoded));
  }

  final List<_StaticSyncCredential> _credentials;

  @override
  bool get isConfigured => _credentials.isNotEmpty;

  @override
  String? authenticate(String token) {
    final candidate = sha256.convert(utf8.encode(token)).bytes;
    for (final credential in _credentials) {
      if (_constantTimeEquals(candidate, credential.tokenHash)) {
        return credential.accountId;
      }
    }
    return null;
  }
}

class ManagedSyncTokenMetadata {
  const ManagedSyncTokenMetadata({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.lastAuthenticatedAt,
  });

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime? lastAuthenticatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'deviceName': deviceName,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastAuthenticatedAt != null)
          'lastAuthenticatedAt': lastAuthenticatedAt!.toUtc().toIso8601String(),
      };
}

class ManagedSyncAccountProfile {
  const ManagedSyncAccountProfile({
    required this.id,
    required this.displayName,
    required this.avatarTone,
    required this.publicProfileEnabled,
    required this.createdAt,
    required this.tokens,
  });

  final String id;
  final String displayName;
  final String? avatarTone;
  final bool publicProfileEnabled;
  final DateTime createdAt;
  final List<ManagedSyncTokenMetadata> tokens;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'displayName': displayName,
        'avatarTone': avatarTone,
        'publicProfileEnabled': publicProfileEnabled,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'tokens': tokens.map((token) => token.toJson()).toList(growable: false),
      };
}

class ManagedSyncPrincipal {
  const ManagedSyncPrincipal({
    required this.accountId,
    required this.token,
  });

  final String accountId;
  final ManagedSyncTokenMetadata token;
}

class IssuedManagedSyncToken {
  const IssuedManagedSyncToken({
    required this.token,
    required this.account,
    required this.device,
    this.replacedTokenId,
  });

  final String token;
  final ManagedSyncAccountProfile account;
  final ManagedSyncTokenMetadata device;
  final String? replacedTokenId;
}

class IssuedManagedRecoveryCode {
  const IssuedManagedRecoveryCode({
    required this.code,
    required this.expiresAt,
  });

  final String code;
  final DateTime expiresAt;
}

class ManagedSyncProfileUpdate {
  const ManagedSyncProfileUpdate({
    required this.account,
    required this.device,
  });

  final ManagedSyncAccountProfile account;
  final ManagedSyncTokenMetadata device;
}

typedef ManagedSyncTokenGenerator = String Function();
typedef ManagedRecoveryCodeGenerator = String Function();

/// Parses the optional managed-token lifetime configured by server operators.
///
/// Omission intentionally retains the historic non-expiring behavior.
Duration? managedTokenLifetimeFromEnvironment(Map<String, String> environment) {
  final rawDays = environment['AETHERTUNE_MANAGED_TOKEN_TTL_DAYS'];
  if (rawDays == null || rawDays.trim().isEmpty) {
    return null;
  }
  final days = int.tryParse(rawDays.trim());
  if (days == null || days < 1 || days > 3650) {
    throw const FormatException(
      'AETHERTUNE_MANAGED_TOKEN_TTL_DAYS must be between 1 and 3650.',
    );
  }
  return Duration(days: days);
}

Duration? _validatedTokenLifetime(Duration? value) {
  if (value != null && value <= Duration.zero) {
    throw ArgumentError.value(value, 'tokenLifetime', 'must be positive.');
  }
  return value;
}

class ManagedSyncAccountRegistry implements SyncAuthenticator {
  ManagedSyncAccountRegistry.memory({
    DateTime Function()? clock,
    ManagedSyncTokenGenerator? tokenGenerator,
    ManagedRecoveryCodeGenerator? recoveryCodeGenerator,
    Duration? tokenLifetime,
  })  : _directory = null,
        _clock = clock ?? DateTime.now,
        _tokenGenerator = tokenGenerator ?? _generateManagedBearerToken,
        _recoveryCodeGenerator =
            recoveryCodeGenerator ?? _generateManagedRecoveryCode,
        _tokenLifetime = _validatedTokenLifetime(tokenLifetime);

  ManagedSyncAccountRegistry._(
    this._directory, {
    DateTime Function()? clock,
    ManagedSyncTokenGenerator? tokenGenerator,
    ManagedRecoveryCodeGenerator? recoveryCodeGenerator,
    Duration? tokenLifetime,
  })  : _clock = clock ?? DateTime.now,
        _tokenGenerator = tokenGenerator ?? _generateManagedBearerToken,
        _recoveryCodeGenerator =
            recoveryCodeGenerator ?? _generateManagedRecoveryCode,
        _tokenLifetime = _validatedTokenLifetime(tokenLifetime);

  static Future<ManagedSyncAccountRegistry> open(
    Directory directory, {
    DateTime Function()? clock,
    ManagedSyncTokenGenerator? tokenGenerator,
    ManagedRecoveryCodeGenerator? recoveryCodeGenerator,
    Duration? tokenLifetime,
  }) async {
    final registry = ManagedSyncAccountRegistry._(
      directory,
      clock: clock,
      tokenGenerator: tokenGenerator,
      recoveryCodeGenerator: recoveryCodeGenerator,
      tokenLifetime: tokenLifetime,
    );
    await registry._load();
    return registry;
  }

  static const maxAccounts = 1000;
  static const maxTokensPerAccount = 32;
  static const activityUpdateInterval = Duration(hours: 24);
  static const recoveryCodeLifetime = Duration(hours: 24);

  final Directory? _directory;
  final DateTime Function() _clock;
  final ManagedSyncTokenGenerator _tokenGenerator;
  final ManagedRecoveryCodeGenerator _recoveryCodeGenerator;
  final Duration? _tokenLifetime;
  Map<String, _ManagedAccountRecord> _accounts =
      <String, _ManagedAccountRecord>{};
  Future<void> _writeTail = Future<void>.value();
  int _revision = 0;

  @override
  bool get isConfigured =>
      _accounts.values.any((account) => account.tokens.isNotEmpty);

  List<ManagedSyncAccountProfile> get accounts {
    final profiles = _accounts.values.map(_profileForRecord).toList();
    profiles.sort((left, right) => left.id.compareTo(right.id));
    return List<ManagedSyncAccountProfile>.unmodifiable(profiles);
  }

  ManagedSyncAccountProfile? account(String accountId) {
    final record = _accounts[accountId];
    return record == null ? null : _profileForRecord(record);
  }

  @override
  String? authenticate(String token) => authenticatePrincipal(token)?.accountId;

  ManagedSyncPrincipal? authenticatePrincipal(String token) {
    final candidate = sha256.convert(utf8.encode(token)).bytes;
    final now = _clock().toUtc();
    for (final account in _accounts.values) {
      for (final storedToken in account.tokens) {
        if (_constantTimeEquals(candidate, storedToken.tokenHash) &&
            !_isTokenExpired(storedToken, now)) {
          return ManagedSyncPrincipal(
            accountId: account.id,
            token: storedToken.metadata,
          );
        }
      }
    }
    return null;
  }

  bool _isTokenExpired(_ManagedTokenRecord token, DateTime now) {
    final lifetime = _tokenLifetime;
    return lifetime != null && !now.isBefore(token.createdAt.add(lifetime));
  }

  /// Records the most recent successful use of a managed device token.
  ///
  /// Activity writes are rate-limited per token to keep normal sync traffic
  /// from turning into a registry write on every request.
  Future<bool> recordAuthenticatedUse({
    required String accountId,
    required String tokenId,
  }) {
    final normalizedAccountId = _validatedAccountId(accountId);
    final normalizedTokenId = tokenId.trim();
    if (!RegExp(r'^[0-9a-f]{24}$').hasMatch(normalizedTokenId)) {
      throw const FormatException('tokenId is invalid.');
    }

    return _serialized(() async {
      final candidate = _copyAccounts();
      final account = candidate[normalizedAccountId];
      if (account == null) {
        return false;
      }
      final tokenIndex = account.tokens.indexWhere(
        (token) => token.id == normalizedTokenId,
      );
      if (tokenIndex < 0) {
        return false;
      }
      final current = account.tokens[tokenIndex];
      final now = _clock().toUtc();
      final previous = current.lastAuthenticatedAt;
      if (previous != null &&
          (!now.isAfter(previous) ||
              now.difference(previous) < activityUpdateInterval)) {
        return false;
      }

      account.tokens[tokenIndex] = current.copyWith(
        lastAuthenticatedAt: now,
      );
      final nextRevision = await _persist(candidate);
      _accounts = candidate;
      _revision = nextRevision;
      return true;
    });
  }

  Future<IssuedManagedSyncToken> issueToken({
    required String accountId,
    required String deviceName,
    String? displayName,
    String? replaceTokenId,
  }) {
    final normalizedAccountId = _validatedAccountId(accountId);
    final normalizedDeviceName = _validatedLabel(
      deviceName,
      fieldName: 'deviceName',
      maxLength: 80,
    );
    final normalizedDisplayName = displayName == null
        ? null
        : _validatedLabel(
            displayName,
            fieldName: 'displayName',
            maxLength: 80,
          );
    final normalizedReplacement = replaceTokenId?.trim();

    return _serialized(() async {
      final candidate = _copyAccounts();
      var account = candidate[normalizedAccountId];
      final now = _clock().toUtc();
      if (account == null) {
        if (candidate.length >= maxAccounts) {
          throw const FormatException('Managed account limit reached.');
        }
        account = _ManagedAccountRecord(
          id: normalizedAccountId,
          displayName: normalizedDisplayName ?? normalizedAccountId,
          createdAt: now,
          tokens: <_ManagedTokenRecord>[],
        );
        candidate[normalizedAccountId] = account;
      } else if (normalizedDisplayName != null) {
        account.displayName = normalizedDisplayName;
      }

      if (normalizedReplacement != null && normalizedReplacement.isNotEmpty) {
        final replacementIndex = account.tokens.indexWhere(
          (token) => token.id == normalizedReplacement,
        );
        if (replacementIndex < 0) {
          throw const FormatException(
            'replaceTokenId does not belong to the account.',
          );
        }
        account.tokens.removeAt(replacementIndex);
      }

      if (account.tokens.any(
        (token) => token.deviceName == normalizedDeviceName,
      )) {
        throw const FormatException(
          'deviceName already has an active token for this account.',
        );
      }
      if (account.tokens.length >= maxTokensPerAccount) {
        throw const FormatException('Managed device token limit reached.');
      }

      final rawToken = _tokenGenerator();
      if (rawToken.isEmpty || RegExp(r'\s').hasMatch(rawToken)) {
        throw StateError('Managed token generation returned an invalid token.');
      }
      final tokenHash = sha256.convert(utf8.encode(rawToken)).bytes;
      final tokenId = _hex(tokenHash).substring(0, 24);
      if (_containsTokenId(candidate, tokenId)) {
        throw StateError('Managed token generation produced a collision.');
      }
      final storedToken = _ManagedTokenRecord(
        id: tokenId,
        deviceName: normalizedDeviceName,
        createdAt: now,
        lastAuthenticatedAt: null,
        tokenHash: tokenHash,
      );
      account.tokens.add(storedToken);

      final nextRevision = await _persist(candidate);
      _accounts = candidate;
      _revision = nextRevision;
      return IssuedManagedSyncToken(
        token: rawToken,
        account: _profileForRecord(account),
        device: storedToken.metadata,
        replacedTokenId: normalizedReplacement,
      );
    });
  }

  Future<IssuedManagedRecoveryCode> issueRecoveryCode({
    required String accountId,
  }) {
    final normalizedAccountId = _validatedAccountId(accountId);
    return _serialized(() async {
      final candidate = _copyAccounts();
      final account = candidate[normalizedAccountId];
      if (account == null) {
        throw const FormatException('Managed account does not exist.');
      }
      final rawCode = _recoveryCodeGenerator();
      if (rawCode.isEmpty || RegExp(r'\s').hasMatch(rawCode)) {
        throw StateError('Recovery code generation returned an invalid code.');
      }
      final now = _clock().toUtc();
      final expiresAt = now.add(recoveryCodeLifetime);
      account.recovery = _ManagedRecoveryRecord(
        codeHash: sha256.convert(utf8.encode(rawCode)).bytes,
        expiresAt: expiresAt,
      );
      final nextRevision = await _persist(candidate);
      _accounts = candidate;
      _revision = nextRevision;
      return IssuedManagedRecoveryCode(code: rawCode, expiresAt: expiresAt);
    });
  }

  Future<IssuedManagedSyncToken?> redeemRecoveryCode({
    required String code,
    required String deviceName,
  }) {
    final normalizedCode = code.trim();
    final normalizedDeviceName = _validatedLabel(
      deviceName,
      fieldName: 'deviceName',
      maxLength: 80,
    );
    if (normalizedCode.isEmpty || RegExp(r'\s').hasMatch(normalizedCode)) {
      throw const FormatException('Recovery code is invalid.');
    }
    final codeHash = sha256.convert(utf8.encode(normalizedCode)).bytes;
    return _serialized(() async {
      final candidate = _copyAccounts();
      final now = _clock().toUtc();
      _ManagedAccountRecord? recoveredAccount;
      for (final account in candidate.values) {
        final recovery = account.recovery;
        if (recovery != null &&
            now.isBefore(recovery.expiresAt) &&
            _constantTimeEquals(codeHash, recovery.codeHash)) {
          recoveredAccount = account;
          break;
        }
      }
      if (recoveredAccount == null) {
        return null;
      }

      recoveredAccount.recovery = null;
      recoveredAccount.tokens.clear();
      final rawToken = _tokenGenerator();
      if (rawToken.isEmpty || RegExp(r'\s').hasMatch(rawToken)) {
        throw StateError('Managed token generation returned an invalid token.');
      }
      final tokenHash = sha256.convert(utf8.encode(rawToken)).bytes;
      final tokenId = _hex(tokenHash).substring(0, 24);
      if (_containsTokenId(candidate, tokenId)) {
        throw StateError('Managed token generation produced a collision.');
      }
      final token = _ManagedTokenRecord(
        id: tokenId,
        deviceName: normalizedDeviceName,
        createdAt: now,
        lastAuthenticatedAt: null,
        tokenHash: tokenHash,
      );
      recoveredAccount.tokens.add(token);
      final nextRevision = await _persist(candidate);
      _accounts = candidate;
      _revision = nextRevision;
      return IssuedManagedSyncToken(
        token: rawToken,
        account: _profileForRecord(recoveredAccount),
        device: token.metadata,
      );
    });
  }

  Future<bool> revokeToken({
    required String accountId,
    required String tokenId,
  }) {
    final normalizedAccountId = _validatedAccountId(accountId);
    final normalizedTokenId = tokenId.trim();
    return _serialized(() async {
      final candidate = _copyAccounts();
      final account = candidate[normalizedAccountId];
      if (account == null) {
        return false;
      }
      final previousLength = account.tokens.length;
      account.tokens.removeWhere(
        (token) => token.id == normalizedTokenId,
      );
      if (account.tokens.length == previousLength) {
        return false;
      }
      final nextRevision = await _persist(candidate);
      _accounts = candidate;
      _revision = nextRevision;
      return true;
    });
  }

  Future<ManagedSyncProfileUpdate?> updateProfile({
    required String accountId,
    required String tokenId,
    String? displayName,
    String? deviceName,
    bool avatarToneProvided = false,
    String? avatarTone,
    bool publicProfileEnabledProvided = false,
    bool publicProfileEnabled = false,
  }) {
    final normalizedAccountId = _validatedAccountId(accountId);
    final normalizedTokenId = tokenId.trim();
    if (!RegExp(r'^[0-9a-f]{24}$').hasMatch(normalizedTokenId)) {
      throw const FormatException('tokenId is invalid.');
    }
    if (displayName == null &&
        deviceName == null &&
        !avatarToneProvided &&
        !publicProfileEnabledProvided) {
      throw const FormatException(
        'At least one profile field must be provided.',
      );
    }
    final normalizedDisplayName = displayName == null
        ? null
        : _validatedLabel(
            displayName,
            fieldName: 'displayName',
            maxLength: 80,
          );
    final normalizedDeviceName = deviceName == null
        ? null
        : _validatedLabel(
            deviceName,
            fieldName: 'deviceName',
            maxLength: 80,
          );
    final normalizedAvatarTone = avatarTone == null
        ? null
        : _validatedAvatarTone(avatarTone);

    return _serialized(() async {
      final candidate = _copyAccounts();
      final account = candidate[normalizedAccountId];
      if (account == null) {
        return null;
      }
      final tokenIndex = account.tokens.indexWhere(
        (token) => token.id == normalizedTokenId,
      );
      if (tokenIndex < 0) {
        return null;
      }
      final currentToken = account.tokens[tokenIndex];
      if (normalizedDeviceName != null &&
          account.tokens.any(
            (token) =>
                token.id != normalizedTokenId &&
                token.deviceName == normalizedDeviceName,
          )) {
        throw const FormatException(
          'deviceName already has an active token for this account.',
        );
      }

      final accountChanged = normalizedDisplayName != null &&
          normalizedDisplayName != account.displayName;
      final deviceChanged = normalizedDeviceName != null &&
          normalizedDeviceName != currentToken.deviceName;
      final avatarChanged = avatarToneProvided &&
          normalizedAvatarTone != account.avatarTone;
      final publicProfileChanged = publicProfileEnabledProvided &&
          publicProfileEnabled != account.publicProfileEnabled;
      if (accountChanged) {
        account.displayName = normalizedDisplayName;
      }
      if (deviceChanged) {
        account.tokens[tokenIndex] = _ManagedTokenRecord(
          id: currentToken.id,
          deviceName: normalizedDeviceName,
          createdAt: currentToken.createdAt,
          lastAuthenticatedAt: currentToken.lastAuthenticatedAt,
          tokenHash: currentToken.tokenHash,
        );
      }
      if (avatarChanged) {
        account.avatarTone = normalizedAvatarTone;
      }
      if (publicProfileChanged) {
        account.publicProfileEnabled = publicProfileEnabled;
      }
      if (accountChanged || deviceChanged || avatarChanged || publicProfileChanged) {
        final nextRevision = await _persist(candidate);
        _accounts = candidate;
        _revision = nextRevision;
      }
      final updatedAccount = accountChanged || deviceChanged
          ? _accounts[normalizedAccountId]!
          : account;
      final updatedToken = updatedAccount.tokens.firstWhere(
        (token) => token.id == normalizedTokenId,
      );
      return ManagedSyncProfileUpdate(
        account: _profileForRecord(updatedAccount),
        device: updatedToken.metadata,
      );
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Map<String, _ManagedAccountRecord> _copyAccounts() {
    return <String, _ManagedAccountRecord>{
      for (final entry in _accounts.entries) entry.key: entry.value.copy(),
    };
  }

  Future<void> _load() async {
    final directory = _directory;
    if (directory == null || !await directory.exists()) {
      return;
    }
    final candidates = <({int revision, File file})>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final match = RegExp(r'^registry-(\d+)\.json$').firstMatch(
        p.basename(entity.path),
      );
      final revision = int.tryParse(match?.group(1) ?? '');
      if (revision != null) {
        candidates.add((revision: revision, file: entity));
      }
    }
    if (candidates.isEmpty) {
      return;
    }
    candidates.sort((left, right) => right.revision.compareTo(left.revision));
    final decoded = jsonDecode(await candidates.first.file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Stored authentication registry is invalid.');
    }
    final document = Map<String, Object?>.from(decoded);
    if (document['version'] != 1 ||
        document['revision'] != candidates.first.revision ||
        document['accounts'] is! List) {
      throw const FormatException('Stored authentication registry is invalid.');
    }
    final loaded = <String, _ManagedAccountRecord>{};
    final loadedTokenIds = <String>{};
    for (final rawAccount in document['accounts']! as List<Object?>) {
      if (rawAccount is! Map) {
        throw const FormatException(
          'Stored authentication account is invalid.',
        );
      }
      final account = _ManagedAccountRecord.fromStorageJson(
        Map<String, Object?>.from(rawAccount),
      );
      if (loaded.containsKey(account.id)) {
        throw const FormatException(
          'Stored authentication account IDs must be unique.',
        );
      }
      for (final token in account.tokens) {
        if (!loadedTokenIds.add(token.id)) {
          throw const FormatException(
            'Stored authentication token IDs must be globally unique.',
          );
        }
      }
      loaded[account.id] = account;
    }
    if (loaded.length > maxAccounts) {
      throw const FormatException(
        'Stored authentication account limit exceeded.',
      );
    }
    _accounts = loaded;
    _revision = candidates.first.revision;
  }

  Future<int> _persist(Map<String, _ManagedAccountRecord> accounts) async {
    final nextRevision = _revision + 1;
    final directory = _directory;
    if (directory == null) {
      return nextRevision;
    }
    await directory.create(recursive: true);
    final finalFile = File(
      p.join(directory.path, 'registry-$nextRevision.json'),
    );
    final temporaryFile = File(
      p.join(
        directory.path,
        '.registry-$nextRevision-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    final orderedAccounts = accounts.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    await temporaryFile.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'revision': nextRevision,
        'accounts': orderedAccounts
            .map((account) => account.toStorageJson())
            .toList(growable: false),
      }),
      flush: true,
    );
    await temporaryFile.rename(finalFile.path);
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path != finalFile.path &&
          RegExp(r'^registry-\d+\.json$').hasMatch(p.basename(entity.path))) {
        try {
          await entity.delete();
        } on FileSystemException {
          // The newest complete registry has already been committed.
        }
      }
    }
    return nextRevision;
  }
}

List<_StaticSyncCredential> _credentialsFromFlatMap(
  Map<String, String> users,
) {
  return <_StaticSyncCredential>[
    for (final entry in users.entries)
      if (entry.key.trim().isNotEmpty && entry.value.isNotEmpty)
        _StaticSyncCredential(
          entry.key.trim(),
          _configuredTokenHash(entry.value),
        ),
  ];
}

List<_StaticSyncCredential> _credentialsFromJsonMap(Map<dynamic, dynamic> map) {
  final credentials = <_StaticSyncCredential>[];
  for (final entry in map.entries) {
    final accountId = _validatedAccountId(entry.key.toString());
    final value = entry.value;
    if (value is String) {
      credentials.add(
        _StaticSyncCredential(accountId, _configuredTokenHash(value)),
      );
      continue;
    }
    final tokens = switch (value) {
      List<dynamic> values => values,
      Map<dynamic, dynamic> values => values.values.toList(growable: false),
      _ => throw const FormatException(
          'AETHERTUNE_SYNC_USERS values must be tokens, token lists, or device-token objects.',
        ),
    };
    for (final token in tokens) {
      if (token is! String) {
        throw const FormatException(
          'AETHERTUNE_SYNC_USERS device tokens must be strings.',
        );
      }
      credentials.add(
        _StaticSyncCredential(accountId, _configuredTokenHash(token)),
      );
    }
  }
  return credentials;
}

List<_StaticSyncCredential> _validatedStaticCredentials(
  List<_StaticSyncCredential> credentials,
) {
  final digests = <String>{};
  for (final credential in credentials) {
    if (!digests.add(_hex(credential.tokenHash))) {
      throw const FormatException(
        'AETHERTUNE_SYNC_USERS tokens must be unique across accounts and devices.',
      );
    }
  }
  return List<_StaticSyncCredential>.unmodifiable(credentials);
}

List<int> _configuredTokenHash(
  String configuredToken, {
  String configurationName = 'AETHERTUNE_SYNC_USERS',
}) {
  if (configuredToken.isEmpty || RegExp(r'\s').hasMatch(configuredToken)) {
    throw FormatException(
      '$configurationName tokens must be non-empty and contain no whitespace.',
    );
  }

  const prefix = 'sha256:';
  if (!configuredToken.startsWith(prefix)) {
    return sha256.convert(utf8.encode(configuredToken)).bytes;
  }

  final hex = configuredToken.substring(prefix.length);
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
    throw FormatException(
      '$configurationName SHA-256 token digests must contain 64 hex characters.',
    );
  }
  return _bytesFromHex(hex);
}

String _validatedAccountId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(normalized)) {
    throw const FormatException(
      'accountId must use 1-64 letters, numbers, dots, underscores, or hyphens.',
    );
  }
  return normalized;
}

String _validatedLabel(
  String value, {
  required String fieldName,
  required int maxLength,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw FormatException(
      '$fieldName must contain 1-$maxLength printable characters.',
    );
  }
  return normalized;
}

String _generateManagedBearerToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return 'at_${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _generateManagedRecoveryCode() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return 'ar_${base64Url.encode(bytes).replaceAll('=', '')}';
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final leftByte = index < left.length ? left[index] : 0;
    final rightByte = index < right.length ? right[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}

List<int> _bytesFromHex(String value) => <int>[
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ];

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

const Set<String> managedProfileAvatarTones = <String>{
  'azure',
  'emerald',
  'amber',
  'rose',
  'violet',
  'slate',
};

String _validatedAvatarTone(String value) {
  final normalized = value.trim().toLowerCase();
  if (!managedProfileAvatarTones.contains(normalized)) {
    throw const FormatException('avatarTone is invalid.');
  }
  return normalized;
}

bool _containsTokenId(
  Map<String, _ManagedAccountRecord> accounts,
  String tokenId,
) {
  return accounts.values.any(
    (account) => account.tokens.any((token) => token.id == tokenId),
  );
}

ManagedSyncAccountProfile _profileForRecord(_ManagedAccountRecord account) {
  final tokens = account.tokens.map((token) => token.metadata).toList()
    ..sort((left, right) {
      final created = left.createdAt.compareTo(right.createdAt);
      return created != 0 ? created : left.id.compareTo(right.id);
    });
  return ManagedSyncAccountProfile(
    id: account.id,
    displayName: account.displayName,
    avatarTone: account.avatarTone,
    publicProfileEnabled: account.publicProfileEnabled,
    createdAt: account.createdAt,
    tokens: List<ManagedSyncTokenMetadata>.unmodifiable(tokens),
  );
}

class _StaticSyncCredential {
  const _StaticSyncCredential(this.accountId, this.tokenHash);

  final String accountId;
  final List<int> tokenHash;
}

class _ManagedAccountRecord {
  _ManagedAccountRecord({
    required this.id,
    required this.displayName,
    this.avatarTone,
    this.publicProfileEnabled = false,
    required this.createdAt,
    required this.tokens,
    this.recovery,
  });

  factory _ManagedAccountRecord.fromStorageJson(Map<String, Object?> json) {
    final id = json['id'];
    final displayName = json['displayName'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final rawTokens = json['tokens'];
    final rawRecovery = json['recovery'];
    final rawAvatarTone = json['avatarTone'];
    final rawPublicProfileEnabled = json['publicProfileEnabled'];
    if (id is! String ||
        displayName is! String ||
        createdAt == null ||
        rawTokens is! List) {
      throw const FormatException('Stored authentication account is invalid.');
    }
    final normalizedId = _validatedAccountId(id);
    final normalizedName = _validatedLabel(
      displayName,
      fieldName: 'displayName',
      maxLength: 80,
    );
    final avatarTone = rawAvatarTone == null
        ? null
        : rawAvatarTone is String
        ? _validatedAvatarTone(rawAvatarTone)
        : throw const FormatException('Stored authentication avatar is invalid.');
    final publicProfileEnabled = rawPublicProfileEnabled == null
        ? false
        : rawPublicProfileEnabled is bool
        ? rawPublicProfileEnabled
        : throw const FormatException('Stored public profile flag is invalid.');
    final tokens = <_ManagedTokenRecord>[];
    final tokenIds = <String>{};
    for (final rawToken in rawTokens) {
      if (rawToken is! Map) {
        throw const FormatException('Stored authentication token is invalid.');
      }
      final token = _ManagedTokenRecord.fromStorageJson(
        Map<String, Object?>.from(rawToken),
      );
      if (!tokenIds.add(token.id)) {
        throw const FormatException(
          'Stored authentication token IDs must be unique.',
        );
      }
      tokens.add(token);
    }
    if (tokens.length > ManagedSyncAccountRegistry.maxTokensPerAccount) {
      throw const FormatException(
        'Stored authentication token limit exceeded.',
      );
    }
    final recovery = rawRecovery == null
        ? null
        : _ManagedRecoveryRecord.fromStorageJson(
            Map<String, Object?>.from(rawRecovery as Map),
          );
    return _ManagedAccountRecord(
      id: normalizedId,
      displayName: normalizedName,
      avatarTone: avatarTone,
      publicProfileEnabled: publicProfileEnabled,
      createdAt: createdAt.toUtc(),
      tokens: tokens,
      recovery: recovery,
    );
  }

  final String id;
  String displayName;
  String? avatarTone;
  bool publicProfileEnabled;
  final DateTime createdAt;
  final List<_ManagedTokenRecord> tokens;
  _ManagedRecoveryRecord? recovery;

  _ManagedAccountRecord copy() => _ManagedAccountRecord(
        id: id,
        displayName: displayName,
        avatarTone: avatarTone,
        publicProfileEnabled: publicProfileEnabled,
        createdAt: createdAt,
        tokens: tokens.map((token) => token.copy()).toList(),
        recovery: recovery?.copy(),
      );

  Map<String, Object?> toStorageJson() => <String, Object?>{
        'id': id,
        'displayName': displayName,
        'avatarTone': avatarTone,
        'publicProfileEnabled': publicProfileEnabled,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'tokens': tokens
            .map((token) => token.toStorageJson())
            .toList(growable: false),
        if (recovery != null) 'recovery': recovery!.toStorageJson(),
      };
}

class _ManagedRecoveryRecord {
  const _ManagedRecoveryRecord({
    required this.codeHash,
    required this.expiresAt,
  });

  factory _ManagedRecoveryRecord.fromStorageJson(Map<String, Object?> json) {
    final hash = json['sha256'];
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        expiresAt == null) {
      throw const FormatException('Stored recovery credential is invalid.');
    }
    return _ManagedRecoveryRecord(
      codeHash: _bytesFromHex(hash),
      expiresAt: expiresAt.toUtc(),
    );
  }

  final List<int> codeHash;
  final DateTime expiresAt;

  _ManagedRecoveryRecord copy() => _ManagedRecoveryRecord(
        codeHash: List<int>.from(codeHash),
        expiresAt: expiresAt,
      );

  Map<String, Object?> toStorageJson() => <String, Object?>{
        'sha256': _hex(codeHash),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };
}

class _ManagedTokenRecord {
  const _ManagedTokenRecord({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.lastAuthenticatedAt,
    required this.tokenHash,
  });

  factory _ManagedTokenRecord.fromStorageJson(Map<String, Object?> json) {
    final id = json['id'];
    final deviceName = json['deviceName'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final rawLastAuthenticatedAt = json['lastAuthenticatedAt'];
    final lastAuthenticatedAt = rawLastAuthenticatedAt == null
        ? null
        : DateTime.tryParse(rawLastAuthenticatedAt as String? ?? '');
    final digest = json['sha256'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{24}$').hasMatch(id) ||
        deviceName is! String ||
        createdAt == null ||
        (rawLastAuthenticatedAt != null && lastAuthenticatedAt == null) ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Stored authentication token is invalid.');
    }
    if (!digest.startsWith(id)) {
      throw const FormatException(
        'Stored authentication token ID does not match its digest.',
      );
    }
    return _ManagedTokenRecord(
      id: id,
      deviceName: _validatedLabel(
        deviceName,
        fieldName: 'deviceName',
        maxLength: 80,
      ),
      createdAt: createdAt.toUtc(),
      lastAuthenticatedAt: lastAuthenticatedAt?.toUtc(),
      tokenHash: _bytesFromHex(digest),
    );
  }

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime? lastAuthenticatedAt;
  final List<int> tokenHash;

  ManagedSyncTokenMetadata get metadata => ManagedSyncTokenMetadata(
        id: id,
        deviceName: deviceName,
        createdAt: createdAt,
        lastAuthenticatedAt: lastAuthenticatedAt,
      );

  _ManagedTokenRecord copyWith({DateTime? lastAuthenticatedAt}) =>
      _ManagedTokenRecord(
        id: id,
        deviceName: deviceName,
        createdAt: createdAt,
        lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
        tokenHash: List<int>.from(tokenHash),
      );

  _ManagedTokenRecord copy() => _ManagedTokenRecord(
        id: id,
        deviceName: deviceName,
        createdAt: createdAt,
        lastAuthenticatedAt: lastAuthenticatedAt,
        tokenHash: List<int>.from(tokenHash),
      );

  Map<String, Object?> toStorageJson() => <String, Object?>{
        'id': id,
        'deviceName': deviceName,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastAuthenticatedAt != null)
          'lastAuthenticatedAt': lastAuthenticatedAt!.toUtc().toIso8601String(),
        'sha256': _hex(tokenHash),
      };
}
