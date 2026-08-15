import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickSingleFile({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  String? dialogTitle,
}) async {
  final file = await FilePicker.pickFile(
    type: type,
    allowedExtensions: allowedExtensions,
    dialogTitle: dialogTitle,
  );
  return file;
}

Future<Uint8List> readPickedFileBytes(PlatformFile file) async {
  return file.readAsBytes();
}
