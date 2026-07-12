import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/playlist_export_file.dart';

void main() {
  test('builds safe playlist filenames for portable exports', () {
    expect(
      playlistExportFileName(
        playlistName: 'Road / Trip: 2026?',
        extension: '.m3u',
      ),
      'Road Trip 2026.m3u',
    );
    expect(
      playlistExportFileName(playlistName: ' . ', extension: 'json'),
      'playlist.json',
    );
  });

  test('requires a file extension', () {
    expect(
      () => playlistExportFileName(playlistName: 'Mix', extension: '  '),
      throwsArgumentError,
    );
  });
}
