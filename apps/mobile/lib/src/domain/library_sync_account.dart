class LibrarySyncAccount {
  const LibrarySyncAccount({
    required this.baseUri,
    required this.deviceId,
    required this.allowInsecureHttp,
  });

  final Uri baseUri;
  final String deviceId;
  final bool allowInsecureHttp;

  bool get usesSecureTransport => baseUri.scheme == 'https';

  Uri get libraryEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'sync', 'library']);

  Uri get libraryMetadataEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'sync', 'library', 'metadata']);

  Uri get listenTogetherEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'listen-together', 'session']);

  Uri get listenTogetherInviteIssueEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'listen-together', 'session', 'invite']);

  Uri listenTogetherInviteEndpointUri(String inviteCode) => _endpointUri(
    <String>['api', 'v1', 'listen-together', 'invites', inviteCode],
  );

  Uri get sharedPlaylistCollectionEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'shared-playlists']);

  Uri sharedPlaylistEndpointUri(String playlistId) =>
      _endpointUri(<String>['api', 'v1', 'shared-playlists', playlistId]);

  Uri sharedPlaylistInviteIssueEndpointUri(String playlistId) => _endpointUri(
    <String>['api', 'v1', 'shared-playlists', playlistId, 'invites'],
  );

  Uri sharedPlaylistInviteEndpointUri(String inviteCode) => _endpointUri(
    <String>['api', 'v1', 'shared-playlist-invites', inviteCode],
  );

  Uri get profileEndpointUri =>
      _endpointUri(<String>['api', 'v1', 'auth', 'profile']);

  Uri _endpointUri(List<String> endpointSegments) {
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: true);
    return baseUri.replace(
      pathSegments: <String>[...baseSegments, ...endpointSegments],
      query: null,
      fragment: null,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'baseUrl': baseUri.toString(),
      'deviceId': deviceId,
      'allowInsecureHttp': allowInsecureHttp,
    };
  }

  factory LibrarySyncAccount.fromJson(Map<String, Object?> json) {
    return createLibrarySyncAccount(
      baseUrl: json['baseUrl'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      allowInsecureHttp: json['allowInsecureHttp'] as bool? ?? false,
    );
  }
}

LibrarySyncAccount createLibrarySyncAccount({
  required String baseUrl,
  required String deviceId,
  required bool allowInsecureHttp,
}) {
  final normalizedDeviceId = deviceId.trim();
  if (normalizedDeviceId.isEmpty) {
    throw const FormatException('Device name is required.');
  }
  if (normalizedDeviceId.length > 128) {
    throw const FormatException('Device name is too long.');
  }

  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      uri.host.trim().isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw const FormatException('Enter a complete HTTP or HTTPS server URL.');
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'Server URL cannot contain credentials, a query, or a fragment.',
    );
  }
  if (uri.scheme == 'http' && !allowInsecureHttp) {
    throw const FormatException(
      'Confirm insecure HTTP before sending the sync token without TLS.',
    );
  }

  final normalizedPath = uri.path == '/'
      ? ''
      : uri.path.replaceFirst(RegExp(r'/+$'), '');
  return LibrarySyncAccount(
    baseUri: uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: normalizedPath,
      query: null,
      fragment: null,
    ),
    deviceId: normalizedDeviceId,
    allowInsecureHttp: allowInsecureHttp,
  );
}
