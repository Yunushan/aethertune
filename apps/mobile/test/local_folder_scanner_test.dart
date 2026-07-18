import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'aethertune-folder-scan-test-',
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('recursively imports supported audio files with folder metadata', () async {
    final albumOne = Directory(p.join(root.path, 'Album One'));
    final discOne = Directory(p.join(albumOne.path, 'Disc 1'));
    await discOne.create(recursive: true);
    await Directory(p.join(root.path, 'Artwork')).create();
    await File(p.join(albumOne.path, '01 Alpha.MP3')).writeAsBytes(<int>[1]);
    await File(
      p.join(discOne.path, '02 Local Artist - Beta.flac'),
    ).writeAsBytes(<int>[2]);
    await File(
      p.join(root.path, 'Loose Artist - Loose Track.m4a'),
    ).writeAsBytes(<int>[3]);
    await File(p.join(root.path, 'cover.jpg')).writeAsBytes(<int>[4]);
    await File(p.join(root.path, 'notes.txt')).writeAsString('not audio');

    final result = await const LocalFolderScanner().scan(
      root.path,
      importedAt: DateTime.utc(2026, 2, 1),
    );

    expect(result.ignoredFileCount, 2);
    expect(result.inaccessibleDirectoryCount, 0);
    expect(
      result.tracks.map((track) => track.title),
      <String>['Alpha', 'Beta', 'Loose Track'],
    );
    expect(
      result.tracks.map((track) => track.album),
      <String>[
        'Album One',
        p.join('Album One', 'Disc 1'),
        p.basename(root.path),
      ],
    );
    expect(
      result.tracks.map((track) => track.artist),
      <String>['Local Folder', 'Local Artist', 'Loose Artist'],
    );
    expect(
      result.tracks.map((track) => track.addedAt).toSet(),
      <DateTime>{DateTime.utc(2026, 2, 1)},
    );
    expect(
      result.tracks.map((track) => track.sourceId).toSet(),
      <String>{'local'},
    );
    expect(
      result.tracks.map((track) => track.contentHash),
      everyElement(isNotEmpty),
    );
    expect(
      result.tracks.first.id,
      Track.stableLocalId(p.join(albumOne.path, '01 Alpha.MP3')),
    );
  });

  test('associates matching LRC sidecar lyrics during folder scans', () async {
    final audioPath = p.join(root.path, 'Sidecar Artist - Sidecar Title.MP3');
    await File(audioPath).writeAsBytes(<int>[1, 2, 3]);
    await File('${p.withoutExtension(audioPath)}.LRC').writeAsString(
      '\ufeff[00:01.00]First line\r\n[00:02.50]Second line\r\n',
    );
    await File(p.join(root.path, 'notes.txt')).writeAsString('not sidecar');

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.ignoredFileCount, 1);
    expect(result.sidecarLyricsCount, 1);
    expect(
      result.sidecarLyricsByTrackId,
      <String, String>{
        Track.stableLocalId(audioPath):
            '[00:01.00]First line\n[00:02.50]Second line',
      },
    );
  });

  test('prefers LRC sidecar lyrics over matching TXT lyrics', () async {
    final audioPath = p.join(root.path, 'Sidecar Artist - Sidecar Title.flac');
    await File(audioPath).writeAsBytes(<int>[1, 2, 3]);
    await File(p.setExtension(audioPath, '.txt')).writeAsString(
      'Plain sidecar lyrics',
    );
    await File(p.setExtension(audioPath, '.lrc')).writeAsString(
      '[00:03.00]Synced sidecar lyrics',
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.ignoredFileCount, 0);
    expect(
      result.sidecarLyricsByTrackId[Track.stableLocalId(audioPath)],
      '[00:03.00]Synced sidecar lyrics',
    );
  });

  test('associates SRT sidecars and skips malformed higher-priority files',
      () async {
    final audioPath = p.join(root.path, 'Timed Artist - Timed Title.ogg');
    await File(audioPath).writeAsBytes(<int>[1, 2, 3]);
    await File(p.setExtension(audioPath, '.ttml')).writeAsString(
      '<tt><body><div><p begin="1s">Broken',
    );
    await File(p.setExtension(audioPath, '.SRT')).writeAsString('''
1
00:00:01,000 --> 00:00:02,000
Timed sidecar
''');

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.ignoredFileCount, 0);
    expect(
      result.sidecarLyricsByTrackId[Track.stableLocalId(audioPath)],
      '1\n00:00:01,000 --> 00:00:02,000\nTimed sidecar',
    );
  });

  test('falls back to matching TXT sidecar lyrics', () async {
    final audioPath = p.join(root.path, 'Plain Artist - Plain Title.wav');
    await File(audioPath).writeAsBytes(<int>[1, 2, 3]);
    await File(p.setExtension(audioPath, '.txt')).writeAsString(
      'First plain line\r\nSecond plain line',
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.sidecarLyricsCount, 1);
    expect(
      result.sidecarLyricsByTrackId[Track.stableLocalId(audioPath)],
      'First plain line\nSecond plain line',
    );
  });

  test('assigns matching content hashes to identical file bytes', () async {
    final first = File(p.join(root.path, 'First.mp3'));
    final second = File(p.join(root.path, 'Second.mp3'));
    final third = File(p.join(root.path, 'Third.mp3'));
    await first.writeAsBytes(<int>[1, 2, 3, 4]);
    await second.writeAsBytes(<int>[1, 2, 3, 4]);
    await third.writeAsBytes(<int>[4, 3, 2, 1]);

    final result = await const LocalFolderScanner().scan(root.path);
    final hashesByTitle = <String, String?>{
      for (final track in result.tracks) track.title: track.contentHash,
    };

    expect(hashesByTitle['First'], hashesByTitle['Second']);
    expect(hashesByTitle['First'], isNot(hashesByTitle['Third']));
    expect(localFileContentHash(<int>[1, 2, 3, 4]), hashesByTitle['First']);
  });

  test('keeps dashed song titles after parsed local artists', () async {
    await File(
      p.join(root.path, '03. Aether Artist - Movement - Live.opus'),
    ).writeAsBytes(<int>[1]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.artist, 'Aether Artist');
    expect(result.tracks.single.title, 'Movement - Live');
  });

  test('prefers ID3v1 title artist and album metadata for MP3 files', () async {
    final albumFolder = Directory(p.join(root.path, 'Filename Album'));
    await albumFolder.create();
    final taggedFile = File(p.join(albumFolder.path, '99 messy-name.mp3'));
    await taggedFile.writeAsBytes(
      <int>[
        1,
        2,
        3,
        ..._id3v1Tag(
          title: 'Tagged Title',
          artist: 'Tagged Artist',
          album: 'Tagged Album',
        ),
      ],
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Tagged Title');
    expect(result.tracks.single.artist, 'Tagged Artist');
    expect(result.tracks.single.album, 'Tagged Album');
  });

  test('prefers ID3v2 title artist album and genre metadata', () async {
    final albumFolder = Directory(p.join(root.path, 'Filename Album'));
    await albumFolder.create();
    final taggedFile = File(p.join(albumFolder.path, '99 messy-name.mp3'));
    await taggedFile.writeAsBytes(
      <int>[
        ..._id3v23Tag(
          title: 'ID3v2 Title',
          artist: 'ID3v2 Artist',
          album: 'ID3v2 Album',
          genre: 'Dream Pop',
        ),
        1,
        2,
        3,
        ..._id3v1Tag(
          title: 'ID3v1 Title',
          artist: 'ID3v1 Artist',
          album: 'ID3v1 Album',
        ),
      ],
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'ID3v2 Title');
    expect(result.tracks.single.artist, 'ID3v2 Artist');
    expect(result.tracks.single.album, 'ID3v2 Album');
    expect(result.tracks.single.genre, 'Dream Pop');
  });

  test('imports ID3 POPM and Vorbis embedded ratings', () async {
    await File(p.join(root.path, 'popm.mp3')).writeAsBytes(<int>[
      ..._id3v23Tag(popularimeterRating: 196),
      1,
    ]);
    await File(p.join(root.path, 'five-stars.flac')).writeAsBytes(
      _flacWithVorbisComments(<String, List<String>>{
        'RATING': <String>['100'],
      }),
    );
    await File(p.join(root.path, 'four-stars.ogg')).writeAsBytes(
      _oggWithVorbisComments(<String, List<String>>{
        'RATING': <String>['4'],
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);
    final ratingsByTitle = <String, int>{
      for (final track in result.tracks) track.title: track.rating,
    };

    expect(ratingsByTitle['popm'], 4);
    expect(ratingsByTitle['five-stars'], 5);
    expect(ratingsByTitle['four-stars'], 4);
  });

  test('reads album artist year and track number across local tag formats',
      () async {
    await File(p.join(root.path, 'mp3.mp3')).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'MP3 Song',
        albumArtist: 'MP3 Album Artist',
        releaseDate: '2024-04-05',
        trackNumber: '2/10',
      ),
      1,
    ]);
    await File(p.join(root.path, 'flac.flac')).writeAsBytes(
      _flacWithVorbisComments(<String, List<String>>{
        'TITLE': <String>['FLAC Song'],
        'ALBUMARTIST': <String>['FLAC Album Artist'],
        'DATE': <String>['2023-11-01'],
        'TRACKNUMBER': <String>['3'],
      }),
    );
    await File(p.join(root.path, 'ogg.ogg')).writeAsBytes(
      _oggWithVorbisComments(<String, List<String>>{
        'TITLE': <String>['Ogg Song'],
        'ALBUMARTIST': <String>['Ogg Album Artist'],
        'YEAR': <String>['2022'],
        'TRACKNUMBER': <String>['4/9'],
      }),
    );
    await File(p.join(root.path, 'opus.opus')).writeAsBytes(
      _oggWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Opus Song'],
          'ALBUMARTIST': <String>['Opus Album Artist'],
          'DATE': <String>['2021'],
          'TRACKNUMBER': <String>['5'],
        },
        opus: true,
      ),
    );
    await File(p.join(root.path, 'm4a.m4a')).writeAsBytes(
      _m4aWithMetadata(
        title: 'M4A Song',
        albumArtist: 'M4A Album Artist',
        releaseDate: '2020-06-12',
        trackNumber: 6,
      ),
    );
    await File(p.join(root.path, 'wav.wav')).writeAsBytes(
      _wavWithInfoTags(<String, String>{
        'INAM': 'WAV Song',
        'ICRD': '2019',
        'ITRK': '7',
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);
    final tracksByTitle = <String, Track>{
      for (final track in result.tracks) track.title: track,
    };

    expect(tracksByTitle['MP3 Song']!.albumArtist, 'MP3 Album Artist');
    expect(tracksByTitle['MP3 Song']!.year, 2024);
    expect(tracksByTitle['MP3 Song']!.trackNumber, 2);
    expect(tracksByTitle['FLAC Song']!.albumArtist, 'FLAC Album Artist');
    expect(tracksByTitle['FLAC Song']!.year, 2023);
    expect(tracksByTitle['FLAC Song']!.trackNumber, 3);
    expect(tracksByTitle['Ogg Song']!.albumArtist, 'Ogg Album Artist');
    expect(tracksByTitle['Ogg Song']!.year, 2022);
    expect(tracksByTitle['Ogg Song']!.trackNumber, 4);
    expect(tracksByTitle['Opus Song']!.albumArtist, 'Opus Album Artist');
    expect(tracksByTitle['Opus Song']!.year, 2021);
    expect(tracksByTitle['Opus Song']!.trackNumber, 5);
    expect(tracksByTitle['M4A Song']!.albumArtist, 'M4A Album Artist');
    expect(tracksByTitle['M4A Song']!.year, 2020);
    expect(tracksByTitle['M4A Song']!.trackNumber, 6);
    expect(tracksByTitle['WAV Song']!.albumArtist, isNull);
    expect(tracksByTitle['WAV Song']!.year, 2019);
    expect(tracksByTitle['WAV Song']!.trackNumber, 7);
  });

  test('extracts ID3v2 embedded artwork for MP3 files', () async {
    await File(p.join(root.path, 'cover-track.mp3')).writeAsBytes(
      <int>[
        ..._id3v23Tag(
          title: 'Artwork Title',
          artist: 'Artwork Artist',
          artworkBytes: _tinyPngBytes,
        ),
        1,
        2,
        3,
      ],
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Artwork Title');
    expect(
      result.tracks.single.artworkUri!.toString(),
      'data:image/png;base64,${base64Encode(_tinyPngBytes)}',
    );
  });

  test('extracts bounded ID3v2 embedded lyrics for MP3 files', () async {
    final audioPath = p.join(root.path, 'embedded-lyrics.mp3');
    await File(audioPath).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'Embedded Lyrics',
        unsynchronizedLyrics: 'First line\r\nSecond line',
      ),
      1,
      2,
      3,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.sidecarLyricsByTrackId, isEmpty);
    expect(result.embeddedLyricsCount, 1);
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(audioPath)],
      'First line\nSecond line',
    );
  });

  test('prefers a lyric sidecar over embedded ID3v2 lyrics', () async {
    final audioPath = p.join(root.path, 'sidecar-wins.mp3');
    await File(audioPath).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'Sidecar Wins',
        unsynchronizedLyrics: 'Embedded lyrics',
      ),
      1,
      2,
      3,
    ]);
    await File(p.setExtension(audioPath, '.lrc')).writeAsString(
      '[00:02.00]Sidecar lyrics',
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(
      result.sidecarLyricsByTrackId[Track.stableLocalId(audioPath)],
      '[00:02.00]Sidecar lyrics',
    );
    expect(result.embeddedLyricsByTrackId, isEmpty);
  });

  test('ignores oversized ID3v2 embedded lyrics', () async {
    final audioPath = p.join(root.path, 'oversized-lyrics.mp3');
    await File(audioPath).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'Bounded lyrics',
        unsynchronizedLyrics: 'x' * (256 * 1024),
      ),
      1,
      2,
      3,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Bounded lyrics');
    expect(result.embeddedLyricsByTrackId, isEmpty);
  });

  test('extracts embedded lyrics from FLAC, Ogg, Opus, and M4A metadata',
      () async {
    final flacPath = p.join(root.path, 'flac-lyrics.flac');
    final oggPath = p.join(root.path, 'ogg-lyrics.ogg');
    final opusPath = p.join(root.path, 'opus-lyrics.opus');
    final m4aPath = p.join(root.path, 'm4a-lyrics.m4a');
    await File(flacPath).writeAsBytes(
      _flacWithVorbisComments(<String, List<String>>{
        'TITLE': <String>['FLAC lyrics'],
        'LYRICS': <String>['FLAC first\r\nFLAC second'],
      }),
    );
    await File(oggPath).writeAsBytes(
      _oggWithVorbisComments(<String, List<String>>{
        'TITLE': <String>['Ogg lyrics'],
        'UNSYNCEDLYRICS': <String>['Ogg first\nOgg second'],
      }),
    );
    await File(opusPath).writeAsBytes(
      _oggWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Opus lyrics'],
          'LYRICS': <String>['Opus first\nOpus second'],
        },
        opus: true,
      ),
    );
    await File(m4aPath).writeAsBytes(
      _m4aWithMetadata(
        title: 'M4A lyrics',
        lyrics: 'M4A first\r\nM4A second',
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(flacPath)],
      'FLAC first\nFLAC second',
    );
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(oggPath)],
      'Ogg first\nOgg second',
    );
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(opusPath)],
      'Opus first\nOpus second',
    );
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(m4aPath)],
      'M4A first\nM4A second',
    );
  });

  test('reads ReplayGain from ID3v2 user text metadata', () async {
    await File(p.join(root.path, 'loud.mp3')).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'ID3 Gain',
        replayGainTrackGain: '-5.10 dB',
        replayGainAlbumGain: '-3.10 dB',
      ),
      1,
      2,
      3,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'ID3 Gain');
    expect(result.tracks.single.replayGainTrackDb, -5.1);
    expect(result.tracks.single.replayGainAlbumDb, -3.1);
  });

  test('merges partial UTF-16 ID3v2 tags with filename metadata', () async {
    await File(
      p.join(root.path, '06 Filename Artist - Filename Title.mp3'),
    ).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'UTF16 Title',
        album: 'UTF16 Album',
        encoding: _id3v2EncodingUtf16,
      ),
      1,
      2,
      3,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'UTF16 Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'UTF16 Album');
  });

  test('prefers FLAC Vorbis comment metadata', () async {
    await File(p.join(root.path, '07 messy-name.flac')).writeAsBytes(
      _flacWithVorbisComments(<String, List<String>>{
        'TITLE': <String>['FLAC Title'],
        'ARTIST': <String>['FLAC Artist', 'Guest Artist'],
        'ALBUM': <String>['FLAC Album'],
        'GENRE': <String>['Ambient', 'Drone'],
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'FLAC Title');
    expect(result.tracks.single.artist, 'FLAC Artist / Guest Artist');
    expect(result.tracks.single.album, 'FLAC Album');
    expect(result.tracks.single.genre, 'Ambient / Drone');
  });

  test('reads Ogg Vorbis and Opus comment metadata', () async {
    await File(p.join(root.path, 'vorbis.ogg')).writeAsBytes(
      _oggWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Ogg Title'],
          'ARTIST': <String>['Ogg Artist'],
          'ALBUM': <String>['Ogg Album'],
          'GENRE': <String>['Shoegaze'],
          'REPLAYGAIN_TRACK_GAIN': <String>['-7.20 dB'],
          'REPLAYGAIN_ALBUM_GAIN': <String>['-5.20 dB'],
        },
      ),
    );
    await File(p.join(root.path, 'spoken.opus')).writeAsBytes(
      _oggWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Opus Title'],
          'ARTIST': <String>['Opus Artist'],
          'ALBUM': <String>['Opus Album'],
          'GENRE': <String>['Spoken Word'],
        },
        opus: true,
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);
    final tracksByTitle = <String, Track>{
      for (final track in result.tracks) track.title: track,
    };

    expect(tracksByTitle['Ogg Title']!.artist, 'Ogg Artist');
    expect(tracksByTitle['Ogg Title']!.album, 'Ogg Album');
    expect(tracksByTitle['Ogg Title']!.genre, 'Shoegaze');
    expect(tracksByTitle['Ogg Title']!.replayGainTrackDb, -7.2);
    expect(tracksByTitle['Ogg Title']!.replayGainAlbumDb, -5.2);
    expect(tracksByTitle['Opus Title']!.artist, 'Opus Artist');
    expect(tracksByTitle['Opus Title']!.album, 'Opus Album');
    expect(tracksByTitle['Opus Title']!.genre, 'Spoken Word');
  });

  test('extracts embedded Ogg Vorbis comment artwork', () async {
    final artwork = <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ];
    await File(p.join(root.path, 'cover.ogg')).writeAsBytes(
      _oggWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Ogg cover'],
          'METADATA_BLOCK_PICTURE': <String>[
            base64.encode(_flacPictureBlock(artwork)),
          ],
        },
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Ogg cover');
    expect(
      result.tracks.single.artworkUri.toString(),
      startsWith('data:image/png;base64,'),
    );
  });

  test('extracts FLAC picture block artwork', () async {
    await File(p.join(root.path, 'picture.flac')).writeAsBytes(
      _flacWithVorbisComments(
        <String, List<String>>{
          'TITLE': <String>['Picture Title'],
        },
        artworkBytes: _tinyPngBytes,
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Picture Title');
    expect(
      result.tracks.single.artworkUri.toString(),
      'data:image/png;base64,${base64Encode(_tinyPngBytes)}',
    );
  });

  test('merges partial FLAC Vorbis comments with filename metadata', () async {
    await File(
      p.join(root.path, '08 Filename Artist - Filename Title.flac'),
    ).writeAsBytes(
      _flacWithVorbisComments(<String, List<String>>{
        'ALBUM': <String>['FLAC Album Only'],
        'GENRE': <String>['Modern Classical'],
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Filename Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'FLAC Album Only');
    expect(result.tracks.single.genre, 'Modern Classical');
  });

  test('prefers M4A metadata atoms', () async {
    await File(p.join(root.path, '09 messy-name.m4a')).writeAsBytes(
      _m4aWithMetadata(
        title: 'M4A Title',
        artist: 'M4A Artist',
        album: 'M4A Album',
        genre: 'Electropop',
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'M4A Title');
    expect(result.tracks.single.artist, 'M4A Artist');
    expect(result.tracks.single.album, 'M4A Album');
    expect(result.tracks.single.genre, 'Electropop');
  });

  test('extracts M4A cover artwork atoms', () async {
    await File(p.join(root.path, 'cover.m4a')).writeAsBytes(
      _m4aWithMetadata(
        title: 'Cover Atom',
        artworkBytes: _tinyPngBytes,
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Cover Atom');
    expect(
      result.tracks.single.artworkUri.toString(),
      'data:image/png;base64,${base64Encode(_tinyPngBytes)}',
    );
  });

  test('reads ReplayGain from M4A freeform metadata', () async {
    await File(p.join(root.path, 'gain.m4a')).writeAsBytes(
      _m4aWithMetadata(
        title: 'M4A Gain',
        replayGainTrackGain: '-4.50 dB',
        replayGainAlbumGain: '-2.50 dB',
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'M4A Gain');
    expect(result.tracks.single.replayGainTrackDb, -4.5);
    expect(result.tracks.single.replayGainAlbumDb, -2.5);
  });

  test('merges partial M4A metadata atoms with filename metadata', () async {
    await File(
      p.join(root.path, '10 Filename Artist - Filename Title.m4a'),
    ).writeAsBytes(
      _m4aWithMetadata(
        album: 'M4A Album Only',
        genre: 'Alternative',
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Filename Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'M4A Album Only');
    expect(result.tracks.single.genre, 'Alternative');
  });

  test('prefers WAV RIFF INFO metadata', () async {
    await File(p.join(root.path, '11 messy-name.wav')).writeAsBytes(
      _wavWithInfoTags(<String, String>{
        'INAM': 'WAV Title',
        'IART': 'WAV Artist',
        'IPRD': 'WAV Album',
        'IGNR': 'Jazz Fusion',
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'WAV Title');
    expect(result.tracks.single.artist, 'WAV Artist');
    expect(result.tracks.single.album, 'WAV Album');
    expect(result.tracks.single.genre, 'Jazz Fusion');
  });

  test('reads WAV RIFF INFO metadata after a data chunk', () async {
    await File(p.join(root.path, '11 data-before-info.wav')).writeAsBytes(
      _wavWithInfoTags(
        <String, String>{
          'INAM': 'Late WAV Title',
          'IART': 'Late WAV Artist',
        },
        leadingDataBytes: 17,
      ),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Late WAV Title');
    expect(result.tracks.single.artist, 'Late WAV Artist');
  });

  test('merges partial WAV RIFF INFO metadata with filename metadata', () async {
    await File(
      p.join(root.path, '12 Filename Artist - Filename Title.wav'),
    ).writeAsBytes(
      _wavWithInfoTags(<String, String>{
        'IPRD': 'WAV Album Only',
        'IGNR': 'Downtempo',
      }),
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Filename Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'WAV Album Only');
    expect(result.tracks.single.genre, 'Downtempo');
  });

  test('falls back to filename metadata when ID3v1 tags are empty', () async {
    await File(
      p.join(root.path, '04 Fallback Artist - Fallback Title.mp3'),
    ).writeAsBytes(<int>[1, 2, 3, ..._id3v1Tag()]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Fallback Title');
    expect(result.tracks.single.artist, 'Fallback Artist');
    expect(result.tracks.single.album, p.basename(root.path));
  });

  test('merges partial ID3v1 tags with filename metadata', () async {
    await File(
      p.join(root.path, '05 Filename Artist - Filename Title.mp3'),
    ).writeAsBytes(<int>[
      1,
      2,
      3,
      ..._id3v1Tag(album: 'Tagged Album Only'),
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Filename Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'Tagged Album Only');
  });

  test('extracts ID3v2 lyric-labelled comment frames only', () async {
    final lyricPath = p.join(root.path, 'comment-lyrics.mp3');
    final notePath = p.join(root.path, 'ordinary-comment.mp3');
    await File(lyricPath).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'Comment Lyrics',
        commentLyrics: 'Comment-frame lyrics',
      ),
      1,
    ]);
    await File(notePath).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'Ordinary Comment',
        commentLyrics: 'Do not import this note',
        commentDescription: 'note',
      ),
      2,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.embeddedLyricsCount, 1);
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(lyricPath)],
      'Comment-frame lyrics',
    );
    expect(
      result.embeddedLyricsByTrackId.containsKey(Track.stableLocalId(notePath)),
      isFalse,
    );
  });

  test('imports bounded APEv2 text metadata before trailing ID3v1', () async {
    final audioPath = p.join(root.path, '99 Filename Artist - Filename Title.mp3');
    await File(audioPath).writeAsBytes(<int>[
      1,
      2,
      3,
      ..._apev2Tag(<String, String>{
        'TITLE': 'APE Title',
        'ARTIST': 'APE Artist',
        'ALBUM': 'APE Album',
        'ALBUM ARTIST': 'APE Album Artist',
        'DATE': '2024-09-01',
        'TRACK': '07/12',
        'GENRE': 'Ambient',
        'REPLAYGAIN_TRACK_GAIN': '-5.40 dB',
        'REPLAYGAIN_ALBUM_GAIN': '-3.25 dB',
        'RATING': '4',
        'LYRICS': 'First line\r\nSecond line',
      }),
      ..._id3v1Tag(
        title: 'ID3v1 Title',
        artist: 'ID3v1 Artist',
        album: 'ID3v1 Album',
      ),
    ]);

    final result = await const LocalFolderScanner().scan(root.path);
    final track = result.tracks.single;

    expect(track.title, 'APE Title');
    expect(track.artist, 'APE Artist');
    expect(track.album, 'APE Album');
    expect(track.albumArtist, 'APE Album Artist');
    expect(track.year, 2024);
    expect(track.trackNumber, 7);
    expect(track.genre, 'Ambient');
    expect(track.replayGainTrackDb, -5.4);
    expect(track.replayGainAlbumDb, -3.25);
    expect(track.rating, 4);
    expect(
      result.embeddedLyricsByTrackId[Track.stableLocalId(audioPath)],
      'First line\nSecond line',
    );
  });

  test('rejects a missing folder path', () async {
    const scanner = LocalFolderScanner();

    expect(
      scanner.scan(p.join(root.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

List<int> _id3v1Tag({
  String title = '',
  String artist = '',
  String album = '',
}) {
  final bytes = List<int>.filled(128, 0);
  bytes[0] = 0x54;
  bytes[1] = 0x41;
  bytes[2] = 0x47;
  _writeFixedAscii(bytes, 3, 30, title);
  _writeFixedAscii(bytes, 33, 30, artist);
  _writeFixedAscii(bytes, 63, 30, album);
  return bytes;
}

List<int> _apev2Tag(Map<String, String> fields) {
  final body = <int>[];
  for (final field in fields.entries) {
    final value = field.value.codeUnits;
    body
      ..addAll(_uint32LittleEndianSize(value.length))
      ..addAll(<int>[0, 0, 0, 0])
      ..addAll(field.key.codeUnits)
      ..add(0)
      ..addAll(value);
  }
  final tagSize = body.length + 32;
  return <int>[
    ...body,
    ...'APETAGEX'.codeUnits,
    ..._uint32LittleEndianSize(2000),
    ..._uint32LittleEndianSize(tagSize),
    ..._uint32LittleEndianSize(fields.length),
    ...List<int>.filled(12, 0),
  ];
}

void _writeFixedAscii(List<int> target, int offset, int length, String value) {
  final codes = value.codeUnits.take(length).toList(growable: false);
  for (var index = 0; index < codes.length; index += 1) {
    target[offset + index] = codes[index];
  }
}

List<int> _id3v23Tag({
  String title = '',
  String artist = '',
  String album = '',
  String albumArtist = '',
  String releaseDate = '',
  String trackNumber = '',
  String genre = '',
  List<int>? artworkBytes,
  String replayGainTrackGain = '',
  String replayGainAlbumGain = '',
  String unsynchronizedLyrics = '',
  String commentLyrics = '',
  String commentDescription = 'lyrics',
  int? popularimeterRating,
  int encoding = _id3v2EncodingUtf8,
}) {
  final frames = <int>[
    if (title.isNotEmpty) ..._id3v23TextFrame('TIT2', title, encoding),
    if (artist.isNotEmpty) ..._id3v23TextFrame('TPE1', artist, encoding),
    if (album.isNotEmpty) ..._id3v23TextFrame('TALB', album, encoding),
    if (albumArtist.isNotEmpty)
      ..._id3v23TextFrame('TPE2', albumArtist, encoding),
    if (releaseDate.isNotEmpty)
      ..._id3v23TextFrame('TDRC', releaseDate, encoding),
    if (trackNumber.isNotEmpty)
      ..._id3v23TextFrame('TRCK', trackNumber, encoding),
    if (genre.isNotEmpty) ..._id3v23TextFrame('TCON', genre, encoding),
    if (artworkBytes != null) ..._id3v23PictureFrame(artworkBytes),
    if (replayGainTrackGain.isNotEmpty)
      ..._id3v23UserTextFrame(
        'REPLAYGAIN_TRACK_GAIN',
        replayGainTrackGain,
        encoding,
      ),
    if (replayGainAlbumGain.isNotEmpty)
      ..._id3v23UserTextFrame(
        'REPLAYGAIN_ALBUM_GAIN',
        replayGainAlbumGain,
        encoding,
      ),
    if (unsynchronizedLyrics.isNotEmpty)
      ..._id3v23UnsynchronizedLyricsFrame(unsynchronizedLyrics, encoding),
    if (commentLyrics.isNotEmpty)
      ..._id3v23CommentFrame(
        commentLyrics,
        commentDescription,
        encoding,
      ),
    if (popularimeterRating != null)
      ..._id3v23PopularimeterFrame(popularimeterRating),
  ];

  return <int>[
    0x49,
    0x44,
    0x33,
    0x03,
    0x00,
    0x00,
    ..._id3v2SynchsafeSize(frames.length),
    ...frames,
  ];
}

List<int> _id3v23PopularimeterFrame(int rating) {
  final payload = <int>[
    ...'aethertune@example.test'.codeUnits,
    0,
    rating,
    0,
    0,
    0,
    0,
  ];
  return <int>[
    ...'POPM'.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v23UnsynchronizedLyricsFrame(String lyrics, int encoding) {
  final terminator = encoding == _id3v2EncodingUtf16
      ? const <int>[0, 0]
      : const <int>[0];
  final payload = <int>[
    encoding,
    ...'eng'.codeUnits,
    ...terminator,
    ..._id3v2EncodedText(lyrics, encoding),
  ];
  return <int>[
    ...'USLT'.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v23CommentFrame(
  String comment,
  String description,
  int encoding,
) {
  final terminator = encoding == _id3v2EncodingUtf16
      ? const <int>[0, 0]
      : const <int>[0];
  final payload = <int>[
    encoding,
    ...'eng'.codeUnits,
    ..._id3v2EncodedText(description, encoding),
    ...terminator,
    ..._id3v2EncodedText(comment, encoding),
  ];
  return <int>[
    ...'COMM'.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v23PictureFrame(List<int> artworkBytes) {
  final payload = <int>[
    _id3v2EncodingUtf8,
    ...'image/png'.codeUnits,
    0,
    3,
    0,
    ...artworkBytes,
  ];

  return <int>[
    ...'APIC'.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v23TextFrame(String id, String value, int encoding) {
  final payload = <int>[
    encoding,
    ..._id3v2EncodedText(value, encoding),
  ];

  return <int>[
    ...id.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v23UserTextFrame(
  String description,
  String value,
  int encoding,
) {
  final terminator = encoding == _id3v2EncodingUtf16
      ? const <int>[0, 0]
      : const <int>[0];
  final payload = <int>[
    encoding,
    ..._id3v2EncodedText(description, encoding),
    ...terminator,
    ..._id3v2EncodedText(value, encoding),
  ];

  return <int>[
    ...'TXXX'.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v2EncodedText(String value, int encoding) {
  if (encoding == _id3v2EncodingUtf16) {
    final bytes = <int>[0xff, 0xfe];
    for (final codeUnit in value.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }

    return bytes;
  }

  return value.codeUnits;
}

List<int> _id3v2SynchsafeSize(int size) {
  return <int>[
    (size >> 21) & 0x7f,
    (size >> 14) & 0x7f,
    (size >> 7) & 0x7f,
    size & 0x7f,
  ];
}

List<int> _uint32Size(int size) {
  return <int>[
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
  ];
}

const _id3v2EncodingUtf8 = 3;
const _id3v2EncodingUtf16 = 1;

List<int> _flacWithVorbisComments(
  Map<String, List<String>> comments, {
  List<int>? artworkBytes,
}) {
  final vorbisComments = _vorbisCommentBlock(comments);
  final pictureBlock =
      artworkBytes == null ? null : _flacPictureBlock(artworkBytes);

  return <int>[
    ...'fLaC'.codeUnits,
    ..._flacMetadataBlockHeader(
      blockType: _flacStreamInfoBlockType,
      length: 34,
      isLast: false,
    ),
    ...List<int>.filled(34, 0),
    ..._flacMetadataBlockHeader(
      blockType: _flacVorbisCommentBlockType,
      length: vorbisComments.length,
      isLast: pictureBlock == null,
    ),
    ...vorbisComments,
    if (pictureBlock != null) ...[
      ..._flacMetadataBlockHeader(
        blockType: _flacPictureBlockType,
        length: pictureBlock.length,
        isLast: true,
      ),
      ...pictureBlock,
    ],
    0,
    1,
    2,
  ];
}

List<int> _flacPictureBlock(List<int> artworkBytes) {
  return <int>[
    ..._uint32Size(3),
    ..._uint32Size('image/png'.codeUnits.length),
    ...'image/png'.codeUnits,
    ..._uint32Size(0),
    ..._uint32Size(1),
    ..._uint32Size(1),
    ..._uint32Size(24),
    ..._uint32Size(0),
    ..._uint32Size(artworkBytes.length),
    ...artworkBytes,
  ];
}

List<int> _vorbisCommentBlock(Map<String, List<String>> comments) {
  final vendor = 'AetherTune Test'.codeUnits;
  final flattenedComments = <String>[
    for (final entry in comments.entries)
      for (final value in entry.value) '${entry.key}=$value',
  ];

  return <int>[
    ..._uint32LittleEndianSize(vendor.length),
    ...vendor,
    ..._uint32LittleEndianSize(flattenedComments.length),
    for (final comment in flattenedComments) ...[
      ..._uint32LittleEndianSize(comment.codeUnits.length),
      ...comment.codeUnits,
    ],
  ];
}

List<int> _oggWithVorbisComments(
  Map<String, List<String>> comments, {
  bool opus = false,
}) {
  final commentPacket = _vorbisCommentBlock(comments);
  final identificationPacket = opus
      ? <int>[...'OpusHead'.codeUnits, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
      : <int>[1, ...'vorbis'.codeUnits, 0, 0, 0, 0];
  final commentsPacket = opus
      ? <int>[...'OpusTags'.codeUnits, ...commentPacket]
      : <int>[3, ...'vorbis'.codeUnits, ...commentPacket];

  return <int>[
    ..._oggPage(identificationPacket, serial: 1, sequence: 0, bos: true),
    ..._oggPage(commentsPacket, serial: 1, sequence: 1),
  ];
}

List<int> _oggPage(
  List<int> packet, {
  required int serial,
  required int sequence,
  bool bos = false,
}) {
  if (packet.length > 255) {
    throw ArgumentError.value(packet.length, 'packet', 'Packet is too large.');
  }

  return <int>[
    ...'OggS'.codeUnits,
    0,
    bos ? 0x02 : 0,
    ...List<int>.filled(8, 0),
    ..._uint32LittleEndianSize(serial),
    ..._uint32LittleEndianSize(sequence),
    ...List<int>.filled(4, 0),
    1,
    packet.length,
    ...packet,
  ];
}

List<int> _flacMetadataBlockHeader({
  required int blockType,
  required int length,
  required bool isLast,
}) {
  return <int>[
    (isLast ? 0x80 : 0x00) | (blockType & 0x7f),
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
  ];
}

List<int> _uint32LittleEndianSize(int size) {
  return <int>[
    size & 0xff,
    (size >> 8) & 0xff,
    (size >> 16) & 0xff,
    (size >> 24) & 0xff,
  ];
}

List<int> _wavWithInfoTags(
  Map<String, String> tags, {
  int leadingDataBytes = 0,
}) {
  final infoPayload = <int>[...'INFO'.codeUnits];
  for (final entry in tags.entries) {
    final valueBytes = <int>[...latin1.encode(entry.value), 0];
    infoPayload
      ..addAll(entry.key.codeUnits)
      ..addAll(_uint32LittleEndianSize(valueBytes.length))
      ..addAll(valueBytes);
    if (valueBytes.length.isOdd) {
      infoPayload.add(0);
    }
  }

  final listChunk = <int>[
    ...'LIST'.codeUnits,
    ..._uint32LittleEndianSize(infoPayload.length),
    ...infoPayload,
  ];
  if (listChunk.length.isOdd) {
    listChunk.add(0);
  }

  final chunks = <int>[];
  if (leadingDataBytes > 0) {
    final dataBytes = List<int>.filled(leadingDataBytes, 0);
    chunks
      ..addAll('data'.codeUnits)
      ..addAll(_uint32LittleEndianSize(dataBytes.length))
      ..addAll(dataBytes);
    if (dataBytes.length.isOdd) {
      chunks.add(0);
    }
  }

  chunks.addAll(listChunk);
  final riffPayload = <int>[...'WAVE'.codeUnits, ...chunks];
  return <int>[
    ...'RIFF'.codeUnits,
    ..._uint32LittleEndianSize(riffPayload.length),
    ...riffPayload,
  ];
}

const _flacStreamInfoBlockType = 0;
const _flacVorbisCommentBlockType = 4;
const _flacPictureBlockType = 6;

List<int> _m4aWithMetadata({
  String title = '',
  String artist = '',
  String album = '',
  String albumArtist = '',
  String releaseDate = '',
  int? trackNumber,
  String genre = '',
  String lyrics = '',
  List<int>? artworkBytes,
  String replayGainTrackGain = '',
  String replayGainAlbumGain = '',
}) {
  final items = <int>[
    if (title.isNotEmpty) ..._m4aTextItem(_m4aTitleAtomType, title),
    if (artist.isNotEmpty) ..._m4aTextItem(_m4aArtistAtomType, artist),
    if (album.isNotEmpty) ..._m4aTextItem(_m4aAlbumAtomType, album),
    if (albumArtist.isNotEmpty)
      ..._m4aTextItem(_m4aAlbumArtistAtomType, albumArtist),
    if (releaseDate.isNotEmpty)
      ..._m4aTextItem(_m4aDateAtomType, releaseDate),
    if (trackNumber != null) ..._m4aTrackNumberItem(trackNumber),
    if (genre.isNotEmpty) ..._m4aTextItem(_m4aGenreAtomType, genre),
    if (lyrics.isNotEmpty) ..._m4aTextItem(_m4aLyricsAtomType, lyrics),
    if (artworkBytes != null) ..._m4aArtworkItem(artworkBytes),
    if (replayGainTrackGain.isNotEmpty)
      ..._m4aReplayGainFreeformItem(replayGainTrackGain),
    if (replayGainAlbumGain.isNotEmpty)
      ..._m4aReplayGainFreeformItem(
        replayGainAlbumGain,
        name: 'REPLAYGAIN_ALBUM_GAIN',
      ),
  ];
  final ilst = _mp4Atom('ilst', items);
  final meta = _mp4Atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _mp4Atom('udta', meta);
  final moov = _mp4Atom('moov', udta);
  final ftyp = _mp4Atom('ftyp', 'M4A '.codeUnits);

  return <int>[
    ...ftyp,
    ...moov,
    ..._mp4Atom('mdat', <int>[0, 1, 2]),
  ];
}

List<int> _m4aTextItem(List<int> atomType, String value) {
  return _mp4AtomBytes(
    atomType,
    _mp4Atom(
      'data',
      <int>[
        ..._uint32Size(1),
        0,
        0,
        0,
        0,
        ...value.codeUnits,
      ],
    ),
  );
}

List<int> _m4aArtworkItem(List<int> artworkBytes) {
  return _mp4Atom(
    'covr',
    _mp4Atom(
      'data',
      <int>[
        ..._uint32Size(14),
        0,
        0,
        0,
        0,
        ...artworkBytes,
      ],
    ),
  );
}

List<int> _m4aTrackNumberItem(int trackNumber) {
  return _mp4Atom(
    'trkn',
    _mp4Atom(
      'data',
      <int>[
        ..._uint32Size(0),
        0,
        0,
        0,
        0,
        0,
        0,
        (trackNumber >> 8) & 0xff,
        trackNumber & 0xff,
        0,
        0,
        0,
        0,
      ],
    ),
  );
}

List<int> _m4aReplayGainFreeformItem(
  String value, {
  String name = 'REPLAYGAIN_TRACK_GAIN',
}) {
  return _mp4Atom(
    '----',
    <int>[
      ..._mp4Atom(
        'mean',
        <int>[0, 0, 0, 0, ...'com.apple.iTunes'.codeUnits],
      ),
      ..._mp4Atom(
        'name',
        <int>[0, 0, 0, 0, ...name.codeUnits],
      ),
      ..._mp4Atom(
        'data',
        <int>[
          ..._uint32Size(1),
          0,
          0,
          0,
          0,
          ...value.codeUnits,
        ],
      ),
    ],
  );
}

List<int> _mp4Atom(String type, List<int> payload) {
  return _mp4AtomBytes(type.codeUnits, payload);
}

List<int> _mp4AtomBytes(List<int> type, List<int> payload) {
  return <int>[
    ..._uint32Size(payload.length + 8),
    ...type,
    ...payload,
  ];
}

const _m4aTitleAtomType = <int>[0xa9, 0x6e, 0x61, 0x6d];
const _m4aArtistAtomType = <int>[0xa9, 0x41, 0x52, 0x54];
const _m4aAlbumAtomType = <int>[0xa9, 0x61, 0x6c, 0x62];
const _m4aAlbumArtistAtomType = <int>[0x61, 0x41, 0x52, 0x54];
const _m4aDateAtomType = <int>[0xa9, 0x64, 0x61, 0x79];
const _m4aGenreAtomType = <int>[0xa9, 0x67, 0x65, 0x6e];
const _m4aLyricsAtomType = <int>[0xa9, 0x6c, 0x79, 0x72];

const _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
