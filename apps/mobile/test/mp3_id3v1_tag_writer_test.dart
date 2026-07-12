import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/mp3_id3v1_tag_writer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-id3-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('appends and replaces ID3v1 title artist and album fields', () async {
    final file = File('${temporaryDirectory.path}/song.mp3');
    await file.writeAsBytes(<int>[1, 2, 3]);
    const writer = Mp3Id3v1TagWriter();

    await writer.write(
      path: file.path,
      title: 'A title',
      artist: 'An artist',
      album: 'An album',
    );

    var bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(bytes.length - 128, bytes.length - 125)), 'TAG');
    expect(_field(bytes, 3, 30), 'A title');
    expect(_field(bytes, 33, 30), 'An artist');
    expect(_field(bytes, 63, 30), 'An album');

    await writer.write(
      path: file.path,
      title: 'Updated',
      artist: 'Unicode ?',
      album: '',
    );
    bytes = await file.readAsBytes();
    expect(_field(bytes, 3, 30), 'Updated');
    expect(_field(bytes, 33, 30), 'Unicode ?');
    expect(_field(bytes, 63, 30), isEmpty);
  });

  test('rejects non-MP3 paths', () async {
    await expectLater(
      const Mp3Id3v1TagWriter().write(
        path: '${Directory.systemTemp.path}/song.flac',
        title: 'Title',
        artist: '',
        album: '',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

String _field(List<int> bytes, int offset, int length) {
  final tagStart = bytes.length - 128;
  return String.fromCharCodes(bytes.sublist(tagStart + offset, tagStart + offset + length))
      .replaceAll(RegExp(r'\x00+$'), '');
}
