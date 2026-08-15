import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickSingleFile({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  String? dialogTitle,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: type,
    allowedExtensions: allowedExtensions,
    dialogTitle: dialogTitle,
    allowMultiple: false,
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty) {
    return null;
  }
  return result.files.first;
}

Future<Uint8List> readPickedFileBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes != null) {
    return bytes;
  }

  final readStream = file.readStream;
  if (readStream != null) {
    final chunks = await readStream.toList();
    return Uint8List.fromList(
      chunks.expand((chunk) => chunk).toList(growable: false),
    );
  }

  return file.xFile.readAsBytes();
}
