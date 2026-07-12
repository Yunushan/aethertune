import 'dart:convert';
import 'dart:typed_data';

const aetherTuneBackupFileExtension = 'json';

String aetherTuneBackupFileName(DateTime timestamp) {
  final utc = timestamp.toUtc();
  final date = <String>[
    utc.year.toString().padLeft(4, '0'),
    utc.month.toString().padLeft(2, '0'),
    utc.day.toString().padLeft(2, '0'),
  ].join();
  final time = <String>[
    utc.hour.toString().padLeft(2, '0'),
    utc.minute.toString().padLeft(2, '0'),
    utc.second.toString().padLeft(2, '0'),
  ].join();
  return 'aethertune-backup-$date-$time.$aetherTuneBackupFileExtension';
}

Uint8List encodeAetherTuneBackupFile(String backupJson) {
  return Uint8List.fromList(utf8.encode(backupJson));
}

String decodeAetherTuneBackupFile(Uint8List bytes) {
  final backupJson = utf8.decode(bytes);
  if (backupJson.trim().isEmpty) {
    throw const FormatException('The selected backup file is empty.');
  }
  return backupJson;
}
