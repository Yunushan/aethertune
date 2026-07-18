import 'package:audio_service_mpris/metadata.dart';
import 'package:audio_service_mpris/mpris.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TrackList exposes stable paths and metadata for the active queue',
    () async {
      final player = OrgMprisMediaPlayer2(identity: 'AetherTune');
      final firstPath = mprisTrackPathForId('local:track/one');
      final secondPath = mprisTrackPathForId('remote:two');

      player.setTracks(<MprisTrack>[
        MprisTrack(
          mediaId: 'local:track/one',
          metadata: Metadata(
            trackId: firstPath,
            title: 'First track',
            artist: const <String>['Artist'],
          ),
        ),
        MprisTrack(
          mediaId: 'remote:two',
          metadata: Metadata(trackId: secondPath, title: 'Second track'),
        ),
      ]);

      expect(player.getHasTrackList().value, isTrue);
      expect(
        player.getTracks().asArray().map((path) => path.asObjectPath()),
        <Object>[firstPath, secondPath],
      );

      final response = await player.doGetTracksMetadata([
        firstPath,
        secondPath,
      ]);
      expect(response, isNotNull);
    },
  );

  test('TrackList GoTo dispatches the matching application media id', () async {
    final player = OrgMprisMediaPlayer2(identity: 'AetherTune');
    final path = mprisTrackPathForId('source:track');
    player.setTracks(<MprisTrack>[
      MprisTrack(
        mediaId: 'source:track',
        metadata: Metadata(trackId: path, title: 'Track'),
      ),
    ]);

    expectLater(player.trackStream, emits('source:track'));
    final response = await player.doGoTo(path);
    expect(response, isNotNull);
  });

  test(
    'Playlists exposes alphabetical entries and activates the chosen list',
    () async {
      final player = OrgMprisMediaPlayer2(identity: 'AetherTune');
      const favorites = MprisPlaylist(
        mediaId: 'aethertune:playlist:favorites',
        name: 'Favorites',
      );
      const archive = MprisPlaylist(
        mediaId: 'aethertune:playlist:archive',
        name: 'Archive',
      );
      player.setPlaylists(<MprisPlaylist>[favorites, archive]);

      expect(player.getPlaylistCount().value, 2);
      expect(player.getOrderings().asArray().single.asString(), 'Alphabetical');
      expect(
        await player.doGetPlaylists(0, 1, 'Alphabetical', false),
        isNotNull,
      );

      expectLater(player.playlistStream, emits(favorites.mediaId));
      final response = await player.doActivatePlaylist(favorites.path);
      expect(response, isNotNull);
    },
  );
}
