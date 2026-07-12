import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aethertune/src/domain/backup_file_document.dart';

void main() {
  test('creates a portable UTC backup filename', () {
    expect(
      aetherTuneBackupFileName(DateTime.utc(2026, 7, 12, 9, 5, 3)),
      'aethertune-backup-20260712-090503.json',
    );
  });

  test('round-trips UTF-8 backup documents without modifying JSON', () {
    const backupJson = '{"version":1,"title":"Istanbul"}';

    expect(
      decodeAetherTuneBackupFile(encodeAetherTuneBackupFile(backupJson)),
      backupJson,
    );
  });

  test('rejects empty and malformed backup files', () {
    expect(
      () => decodeAetherTuneBackupFile(Uint8List(0)),
      throwsFormatException,
    );
    expect(
      () => decodeAetherTuneBackupFile(Uint8List.fromList(<int>[0xc3, 0x28])),
      throwsFormatException,
    );
  });
}
