import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class LibrarySyncCredentialVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

final class SecureLibrarySyncCredentialVault
    implements LibrarySyncCredentialVault {
  SecureLibrarySyncCredentialVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'aethertune.library_sync.token.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
