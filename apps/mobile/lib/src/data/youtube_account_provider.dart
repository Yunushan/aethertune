import 'dart:convert';
import 'dart:io';

import 'youtube_data_metadata_provider.dart';

typedef YouTubeAccessTokenReader = Future<String> Function();
typedef YouTubeAccountResponseLoader = Future<String> Function(
  Uri uri,
  String accessToken,
);

/// Read-only, bearer-authorized views of a listener's own YouTube account.
///
/// This does not expose a stream URI, alter a YouTube resource, or persist
/// account metadata. The caller owns token refresh and secure storage.
final class YouTubeAccountProvider {
  YouTubeAccountProvider({
    required YouTubeAccessTokenReader accessTokenReader,
    Uri? playlistsUri,
    Uri? subscriptionsUri,
    YouTubeAccountResponseLoader? responseLoader,
  }) : _accessTokenReader = accessTokenReader,
       playlistsUri = playlistsUri ?? _defaultPlaylistsUri,
       subscriptionsUri = subscriptionsUri ?? _defaultSubscriptionsUri,
       _responseLoader = responseLoader ?? _loadAuthorizedJson;

  static final Uri _defaultPlaylistsUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/playlists',
  );
  static final Uri _defaultSubscriptionsUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/subscriptions',
  );

  final YouTubeAccessTokenReader _accessTokenReader;
  final YouTubeAccountResponseLoader _responseLoader;
  final Uri playlistsUri;
  final Uri subscriptionsUri;

  Future<YouTubeDataPlaylistPage> loadMyPlaylistsPage({
    String? cursor,
    int limit = 20,
  }) async {
    final normalizedCursor = _normalizeCursor(cursor);
    final accessToken = await _accessTokenReader();
    return parseYouTubeDataPlaylistPage(
      await _responseLoader(
        playlistsUri.replace(
          queryParameters: _queryParameters(
            cursor: normalizedCursor,
            part: 'snippet,contentDetails',
            limit: limit,
            mine: true,
          ),
        ),
        _requireAccessToken(accessToken),
      ),
    );
  }

  Future<YouTubeDataChannelPage> loadMySubscriptionsPage({
    String? cursor,
    int limit = 20,
  }) async {
    final normalizedCursor = _normalizeCursor(cursor);
    final accessToken = await _accessTokenReader();
    return parseYouTubeDataChannelPage(
      await _responseLoader(
        subscriptionsUri.replace(
          queryParameters: _queryParameters(
            cursor: normalizedCursor,
            part: 'snippet',
            limit: limit,
            order: 'alphabetical',
            mine: true,
          ),
        ),
        _requireAccessToken(accessToken),
      ),
    );
  }

  Future<YouTubeDataPlaylistItemsPage> loadPlaylistItemsPage(
    String playlistId, {
    String? cursor,
    int limit = 20,
  }) async {
    final normalizedPlaylistId = playlistId.trim();
    if (normalizedPlaylistId.isEmpty) {
      throw const FormatException('Select a YouTube playlist first.');
    }
    final normalizedCursor = _normalizeCursor(cursor);
    final accessToken = await _accessTokenReader();
    return parseYouTubeDataPlaylistItemsPage(
      await _responseLoader(
        playlistsUri.resolve('playlistItems').replace(
          queryParameters: _queryParameters(
            cursor: normalizedCursor,
            part: 'snippet,contentDetails',
            limit: limit,
            extra: <String, String>{'playlistId': normalizedPlaylistId},
          ),
        ),
        _requireAccessToken(accessToken),
      ),
    );
  }
}

int _limit(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'limit', 'Must be positive.');
  }
  return value.clamp(1, 50);
}

Map<String, String> _queryParameters({
  required String? cursor,
  required String part,
  required int limit,
  bool mine = false,
  String? order,
  Map<String, String> extra = const <String, String>{},
}) {
  final parameters = <String, String>{
    'part': part,
    'maxResults': _limit(limit).toString(),
    ...extra,
  };
  if (mine) {
    parameters['mine'] = 'true';
  }
  if (order != null) {
    parameters['order'] = order;
  }
  if (cursor != null) {
    parameters['pageToken'] = cursor;
  }
  return parameters;
}

String? _normalizeCursor(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String _requireAccessToken(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw StateError('YouTube account access is unavailable.');
  }
  return normalized;
}

Future<String> _loadAuthorizedJson(Uri uri, String accessToken) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube account metadata request failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
