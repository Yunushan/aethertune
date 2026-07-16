/// The portable AetherTune link kinds that the app can import directly.
enum AetherTuneDeepLinkKind { playlist, smartPlaylist }

/// A validated route shell for a custom `aethertune://` URL.
///
/// The store still validates payload size, encoding, document version, and
/// track matching before making any library change.
class AetherTuneDeepLink {
  const AetherTuneDeepLink({required this.uri, required this.kind});

  final Uri uri;
  final AetherTuneDeepLinkKind kind;

  static AetherTuneDeepLink? tryParse(Uri uri) {
    if (uri.scheme.toLowerCase() != 'aethertune') {
      return null;
    }
    switch (uri.host.toLowerCase()) {
      case 'playlist':
        return AetherTuneDeepLink(
          uri: uri,
          kind: AetherTuneDeepLinkKind.playlist,
        );
      case 'smart-playlist':
        return AetherTuneDeepLink(
          uri: uri,
          kind: AetherTuneDeepLinkKind.smartPlaylist,
        );
    }
    return null;
  }
}
