import 'dart:typed_data';

import 'package:aethertune/src/data/file_picker_adapter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads inline picker bytes without a platform channel', () async {
    final file = PlatformFile(
      name: 'sample.txt',
      size: 3,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(await readPickedFileBytes(file), orderedEquals(<int>[1, 2, 3]));
  });

  test('reads a picker stream when bytes were not loaded eagerly', () async {
    final file = PlatformFile(
      name: 'sample.txt',
      size: 4,
      readStream: Stream<List<int>>.fromIterable(const <List<int>>[
        <int>[4, 5],
        <int>[6, 7],
      ]),
    );

    expect(await readPickedFileBytes(file), orderedEquals(<int>[4, 5, 6, 7]));
  });
}
