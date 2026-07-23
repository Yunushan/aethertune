import 'package:path/path.dart' as path;

import '../domain/track.dart';
import '../domain/track_chapter.dart';
import 'android_audio_library_access.dart';
import 'local_folder_scanner.dart';
import 'local_media_uri.dart';

/// Scans a persisted Android document tree through a temporary, private
/// materialization. Saved tracks retain their content URIs, never cache paths.
Future<LocalFolderScanResult> scanPersistedAndroidSafTreeInBackground(
  String treeUri, {
  DateTime? importedAt,
  LocalFolderScanProgressListener? onProgress,
}) async {
  if (!isContentMediaUri(treeUri)) {
    throw const FormatException('A persisted Android content URI is required.');
  }
  final materialization = await AndroidAudioLibraryAccess.materializeTree(
    treeUri,
  );
  try {
    final scanned = await scanLocalFolderInBackground(
      materialization.stagingRootPath,
      importedAt: importedAt,
      onProgress: onProgress,
    );
    return _rebindSafScanResult(scanned, materialization);
  } finally {
    await AndroidAudioLibraryAccess.discardMaterialization(
      materialization.stagingRootPath,
    );
  }
}

Future<LocalFolderScanResult> scanLocalFolderWithSafSupportInBackground(
  String rootPath, {
  DateTime? importedAt,
  LocalFolderScanProgressListener? onProgress,
}) {
  if (isContentMediaUri(rootPath)) {
    return scanPersistedAndroidSafTreeInBackground(
      rootPath,
      importedAt: importedAt,
      onProgress: onProgress,
    );
  }
  return scanLocalFolderInBackground(
    rootPath,
    importedAt: importedAt,
    onProgress: onProgress,
  );
}

LocalFolderScanResult _rebindSafScanResult(
  LocalFolderScanResult scanned,
  AndroidSafTreeMaterialization materialization,
) {
  final sourceByStagedPath = <String, String>{
    for (final entry in materialization.sourceUriByRelativePath.entries)
      path.normalize(path.absolute(path.join(
        materialization.stagingRootPath,
        entry.key,
      ))): entry.value,
  };
  final reboundIdByScannedId = <String, String>{};
  final tracks = <Track>[];
  for (final track in scanned.tracks) {
    final localPath = track.localPath;
    if (localPath == null) {
      tracks.add(track);
      continue;
    }
    final sourceUri = sourceByStagedPath[path.normalize(path.absolute(localPath))];
    if (sourceUri == null) {
      tracks.add(track);
      continue;
    }
    final sourceId = Track.stableLocalId(sourceUri);
    reboundIdByScannedId[track.id] = sourceId;
    tracks.add(track.copyWith(id: sourceId, localPath: sourceUri));
  }
  return LocalFolderScanResult(
    tracks: List.unmodifiable(tracks),
    ignoredFileCount: scanned.ignoredFileCount,
    inaccessibleDirectoryCount:
        scanned.inaccessibleDirectoryCount +
        materialization.inaccessibleDirectoryCount,
    sidecarLyricsByTrackId: _rebindStringMap(
      scanned.sidecarLyricsByTrackId,
      reboundIdByScannedId,
    ),
    embeddedLyricsByTrackId: _rebindStringMap(
      scanned.embeddedLyricsByTrackId,
      reboundIdByScannedId,
    ),
    sidecarChaptersByTrackId: _rebindChapterMap(
      scanned.sidecarChaptersByTrackId,
      reboundIdByScannedId,
    ),
  );
}

Map<String, String> _rebindStringMap(
  Map<String, String> values,
  Map<String, String> reboundIdByScannedId,
) {
  return Map.unmodifiable(<String, String>{
    for (final entry in values.entries)
      reboundIdByScannedId[entry.key] ?? entry.key: entry.value,
  });
}

Map<String, List<TrackChapter>> _rebindChapterMap(
  Map<String, List<TrackChapter>> values,
  Map<String, String> reboundIdByScannedId,
) {
  return Map.unmodifiable(<String, List<TrackChapter>>{
    for (final entry in values.entries)
      reboundIdByScannedId[entry.key] ?? entry.key: entry.value,
  });
}
