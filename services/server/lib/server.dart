import 'dart:convert';

import 'package:shelf/shelf.dart';

const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

const _tracks = <CatalogTrack>[
  CatalogTrack(
    id: 'local-files',
    title: 'Local Files',
    artist: 'AetherTune',
    album: 'Core Sources',
    sourceId: 'local',
  ),
  CatalogTrack(
    id: 'self-hosted',
    title: 'Self-hosted Library',
    artist: 'Jellyfin / Navidrome / Subsonic',
    album: 'Server Roadmap',
    sourceId: 'self-hosted',
  ),
  CatalogTrack(
    id: 'open-catalogs',
    title: 'Open Catalogs',
    artist: 'Podcasts / Radio / Internet Archive',
    album: 'Provider Roadmap',
    sourceId: 'open-catalogs',
  ),
];

Handler createServerHandler({DateTime Function()? clock}) {
  final now = clock ?? DateTime.now;

  return (Request request) async {
    if (request.method != 'GET') {
      return _jsonResponse(
        405,
        <String, Object?>{
          'error': 'method_not_allowed',
          'method': request.method,
        },
      );
    }

    switch (request.url.path) {
      case 'health':
        return _jsonResponse(
          200,
          <String, Object?>{
            'status': 'ok',
            'service': 'aethertune-server',
            'timestamp': now().toUtc().toIso8601String(),
          },
        );
      case 'api/v1/info':
        return _jsonResponse(
          200,
          <String, Object?>{
            'name': 'AetherTune',
            'service': 'aethertune-server',
            'version': '0.1.0',
            'supportedClients': <String>[
              'android',
              'ios',
              'linux',
              'macos',
              'windows',
            ],
          },
        );
      case 'api/v1/tracks':
        final query = request.url.queryParameters['q'] ?? '';
        return _jsonResponse(
          200,
          <String, Object?>{
            'tracks': searchCatalog(query)
                .map((track) => track.toJson())
                .toList(growable: false),
          },
        );
      default:
        return _jsonResponse(
          404,
          <String, Object?>{
            'error': 'not_found',
            'path': '/${request.url.path}',
          },
        );
    }
  };
}

List<CatalogTrack> searchCatalog(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return _tracks;
  }

  return _tracks.where((track) => track.matches(normalized)).toList();
}

Response _jsonResponse(int statusCode, Map<String, Object?> body) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: _jsonHeaders,
  );
}

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.sourceId,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String sourceId;

  bool matches(String query) {
    return title.toLowerCase().contains(query) ||
        artist.toLowerCase().contains(query) ||
        album.toLowerCase().contains(query) ||
        sourceId.toLowerCase().contains(query);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'sourceId': sourceId,
    };
  }
}
