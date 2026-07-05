import 'track.dart';

/// Implement this contract to add a legal source adapter.
///
/// Examples: local files, user-owned Jellyfin/Navidrome server, podcasts,
/// Internet Archive, Radio Browser, or any official/documented music API.
abstract interface class MusicSourceProvider {
  String get id;
  String get name;
  String get description;

  /// Search metadata inside the provider.
  Future<List<Track>> search(String query);

  /// Resolve a playable URI. Providers can return null when the track is only
  /// metadata or when user authorization is required.
  Future<Uri?> resolveStream(Track track);
}
