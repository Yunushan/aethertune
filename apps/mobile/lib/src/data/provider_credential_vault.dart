import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProviderCredentialVault {
  Future<String?> read(String accountId);
  Future<void> write(String accountId, String secret);
  Future<void> delete(String accountId);
}

final class SecureProviderCredentialVault implements ProviderCredentialVault {
  SecureProviderCredentialVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'aethertune.provider.secret.v1.';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String accountId) {
    return _storage.read(key: _key(accountId));
  }

  @override
  Future<void> write(String accountId, String secret) {
    return _storage.write(key: _key(accountId), value: secret);
  }

  @override
  Future<void> delete(String accountId) {
    return _storage.delete(key: _key(accountId));
  }

  String _key(String accountId) => '$_keyPrefix$accountId';
}
