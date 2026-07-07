# User Guide

## Install for development

```bash
./scripts/bootstrap_client.sh
cd apps/mobile
flutter run
```

For desktop development, run the same Flutter package on a desktop target:

```bash
cd apps/mobile
flutter run -d linux
flutter run -d macos
flutter run -d windows
```

For server development:

```bash
cd services/server
dart pub get
dart run bin/server.dart
```

## Import local music

1. Open the app.
2. Tap the library-add icon in the top-right corner.
3. Select one or more audio files.
4. Tap a track to play it.

## Search

Use the search box on the Library tab. Search matches:

- title
- artist
- album/folder
- genre

Use the sort button in the search bar to order the library by recently added, title, artist, or album. Use the Artists, Albums, Genres, Sources, and Folders chips below the search bar to browse grouped library views and play a group as a queue.

## Favorites

Open a track menu and choose **Favorite**. Use the heart button in the search bar to filter favorites.

## Queue controls

When you play a track from the library, the current filtered list becomes the queue. AetherTune restores that queue when you reopen the app. Use previous/next controls in the player bar, the queue button to move tracks up/down or remove upcoming tracks, or the playlist-add button to save the current queue as a playlist.

## History

The History tab shows recently played library tracks, local play counts, and last played times. Tap a track to play it again or use the clear button to remove local listening history.

## Playlists

Use the Playlists tab to open built-in smart playlists for favorites, recently added tracks, recently played tracks, and most played tracks. You can also create, rename, delete, open, search within, reorder, import, export, and play manual playlists. Add tracks from the Library tab by opening a track menu and choosing **Add to playlist**. Use the import button to paste JSON, M3U, or CSV playlist content; imports link tracks that already exist in your local library. Use a playlist menu to export JSON/M3U/CSV. Open a playlist and use the search box to find tracks by title, artist, or album; use a track menu to move a track up, move it down, or remove it.

## Lyrics

Open a track menu in the Library tab and choose **Lyrics**. You can save plain text lyrics for that track, paste LRC timestamped lyrics to preview timed lines, edit them later, or delete them from the same dialog. While a track is playing, use the lyrics button in the player bar to open now-playing lyrics; LRC lines highlight and scroll with playback.

## Backup and restore

Open the Options tab and choose **Export backup** to view a versioned JSON backup. Choose **Restore backup** and paste a backup JSON to replace the local library, playlists, lyrics, history, podcast feed subscriptions, and podcast episode progress with that backup.

## Sleep timer

Tap the moon icon in the top-right corner and choose a preset duration, choose **Custom duration** and enter 1 to 1440 minutes, or choose **Stop at end of current track**. Playback stops automatically when the timer or selected track ends.

## Options

The Options tab contains playback settings such as shuffle and repeat mode. AetherTune restores those playback settings when you reopen the app.

## Provider plugins

The Sources tab explains the provider model and shows capability/privacy disclosure for enabled adapters. The current app includes:

- Local Files: working.
- Demo Provider: template with declared search capability and no network access.
- Podcast RSS: add a legal RSS feed URL in Sources, import/export OPML, then load, play, resume, save, or remove feed episodes.
- Radio Browser: search public internet radio stations in Sources, then play a station or save it to the local library.
- Self-hosted/open providers: roadmap.
- Commercial services: official APIs only.
