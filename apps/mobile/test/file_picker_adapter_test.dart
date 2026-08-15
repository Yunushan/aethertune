import 'dart:typed_data';

import 'package:aethertune/src/data/file_picker_adapter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

base class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile({
    required this.fileName,
    this.bytes,
    this.byteStream,
  });

  final String fileName;
  final Uint8List? bytes;
  final Stream<Uint8List>? byteStream;

  @override
  String get name => fileName;

  @override
  Uri get uri => Uri.file('/tmp/$fileName');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  Future<int> length() async {
    if (bytes != null) {
      return bytes!.length;
    }
    return (await readAsBytes()).length;
  }

  @override
  Future<Uint8List> readAsBytes() async {
    if (bytes != null) {
      return bytes!;
    }
    final chunks = await readAsByteStream().toList();
    return Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
  }

  @override
  Stream<Uint8List> readAsByteStream() {
    return byteStream ?? Stream<Uint8List>.value(bytes!);
  }
}

void main() {
  test('reads inline picker bytes without a platform channel', () async {
    final file = _TestPlatformFile(
      fileName: 'sample.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(await readPickedFileBytes(file), orderedEquals(<int>[1, 2, 3]));
  });

  test('reads a picker stream when bytes were not loaded eagerly', () async {
    final file = _TestPlatformFile(
      fileName: 'sample.txt',
      byteStream: Stream<Uint8List>.fromIterable(<Uint8List>[
        Uint8List.fromList(<int>[4, 5]),
        Uint8List.fromList(<int>[6, 7]),
      ]),
    );

    expect(await readPickedFileBytes(file), orderedEquals(<int>[4, 5, 6, 7]));
  });
}
