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
2. Tap the library-add icon in the top-right corner to select one or more audio files, or tap the folder icon to scan a folder recursively.
3. AetherTune imports supported audio files, reads basic ID3v1 MP3 title/artist/album tags, ID3v2 MP3 title/artist/album/genre text tags plus APIC/PIC artwork, FLAC Vorbis comment title/artist/album/genre tags plus picture artwork, M4A title/artist/album/genre metadata atoms plus `covr` artwork, and WAV RIFF INFO title/artist/album/genre tags during folder scans, attaches matching basename `.lrc` or `.txt` lyric sidecars without replacing lyrics you already saved, parses common filename metadata such as leading track numbers and `Artist - Title` when tags are missing, and groups folder-scanned tracks by their parent folders.
4. Tap a track to play it.

## Home

The Home tab shows local feed sections for recommendations, mood/activity mixes, in-progress tracks, recently played tracks, radio seeds with local matches, most played tracks, favorites, recently added tracks, and local charts. The "For you" section uses favorites and recent playback as local taste signals while skipping just-played tracks. Focus, Energy, Chill, Workout, and Sleep mixes are generated from playable library metadata. The chart range selector can show all-time, last-7-days, last-30-days, or last-year top tracks, artists, albums, and genres from playback history. Tap a track to play that section as the queue, or open its menu for lyrics, playlists, metadata edits, favorites, removal, radio, and **Copy share text**.

On desktop-width windows, AetherTune uses a labeled left navigation rail instead of bottom navigation so Home, Library, Playlists, History, Sources, and Options stay visible beside the content and player bar.

## Search

Use the search box on the Library tab. Search matches:

- title
- artist
- album/folder
- genre
- source
- saved plain or LRC lyrics

Saved synced LRC lyrics are searched by their visible lyric text, not by timestamp tags. Library, playlist, suggestion, browse, and saved-lyrics searches tolerate small typos in meaningful search terms. Suggestion chips below the search bar come from submitted searches, recently played tracks, and library metadata. Use the sort button in the search bar to order the library by recently added, title, artist, or album. Use the cloud-off button to show only local files that can play while offline mode is enabled. Use the Artists, Albums, Genres, Sources, and Folders chips below the search bar to browse grouped library views and play a group as a queue. The Folders chip shows a recursive tree with parent folders, child folders, aggregate track counts, and descendant playback queues. Open a browse group or folder node and use the share icon to copy privacy-safe share text; local file paths are not included. Open a track menu and choose **Similar tracks** to find playable local tracks with matching artist, album, or genre metadata; the sheet explains each match and can play the results as a queue.

## Metadata

Open a track menu and choose **Edit metadata** to update the saved title, artist, album, or genre. These edits update library search, browse groups, playlists, suggestions, and backups.

## Duplicate resolver

Open the Options tab and choose **Resolve duplicates** when duplicate groups are found. AetherTune can match duplicate library entries by same local path, scanner content hash, provider item, stream URL, or metadata plus known duration. Choose **Keep** on the track you want to preserve; playlists, favorites, lyrics, history, and playback progress are merged into that kept track.

## Favorites

Open a track menu and choose **Favorite**. Use the heart button in the search bar to filter favorites.

## Queue controls

When you play a track from the library, the current filtered list becomes one lazy native playlist so the audio engine can prepare and transition to the next item without AetherTune reloading each track. Android, iOS, and macOS use the native `just_audio` backends; Windows and Linux use the bundled MediaKit audio backend with playlist prefetch. Open a track menu and choose **Start radio** to build a local seed queue from playable tracks with matching artist, genre, or album, ranked by favorites and play history. Use **Copy share text** from a track menu to copy track metadata and a web link when one exists; local paths are redacted. The **Similar tracks** sheet can also play its matched result list as the queue. AetherTune restores the current queue when you reopen the app. Use previous/next controls in the player bar, the queue button to move tracks up/down or remove upcoming tracks while preserving the current position, or the playlist-add button to save the current queue as a playlist. Offline mode rebuilds the native queue with local files only.

On Android, the media notification and headset buttons show the current title, artist, album, artwork, queue position, playback position, and available previous/play-pause/next/stop actions. On iOS and macOS, the same queue metadata and controls are published to Control Center and Now Playing surfaces. System seek, repeat, and shuffle commands are routed to the same queue engine as the in-app controls. Android and iOS are configured for background music playback; operating-system battery policy, audio interruptions, route changes, and device-specific lifecycle behavior still need physical-device validation before release.

## History

The History tab shows a local listening recap with library totals, favorites, play count, estimated listening time, responsive top-track and top-artist charts, monthly and yearly calendar recap cards, top tracks, top artists, top albums, top genres, recently played library tracks, individual play history entries, and last played times. Use the bookmarks icon to save the current date range and history search as a named view; saved views can be applied, updated to the current filters, renamed, or deleted and are included in backups. Use the image icon on a monthly or yearly card to preview a share visual and save it as a PNG through the platform file dialog. Use **Pause listening history** to stop saving new plays and resume progress while keeping existing history until you clear it. Use the range selector to view all-time, last 7 days, last 30 days, or last-year stats; use the export button to copy the selected range as JSON or CSV. Use **Search listening history** to filter recently played tracks and individual play entries by title, artist, album, genre, source, folder, or saved lyrics. Tap a track to play it again, use the delete icon beside a play history entry to remove only that play, or use the clear button to remove all local listening history.

## Playlists

Use the Playlists tab to open built-in smart playlists for favorites, recently added tracks, recently played tracks, and most played tracks. Create custom smart playlists with search text, favorites-only, minimum play count, sort mode, and result limit rules; AetherTune updates their tracks dynamically as the library changes. Search text matches saved lyrics as well as metadata. You can also create, rename, edit artwork URLs, delete, open, search within, reorder, import, export, and play manual playlists. Add tracks from the Library tab by opening a track menu and choosing **Add to playlist**. Use the import button to paste JSON, M3U, or CSV playlist content; imports link tracks that already exist in your local library and preserve AetherTune playlist artwork URLs from JSON exports. Use a playlist menu to export JSON/M3U/CSV, choose **Copy share text**, or set/clear an http or https artwork image URL. Open a playlist and use the search box to find tracks by title, artist, album, or saved lyrics; use a track menu to move a track up, move it down, or remove it.

## Lyrics

Open a track menu in the Library tab and choose **Lyrics**. You can save plain text lyrics for that track, import a UTF-8 `.txt` or `.lrc` file, paste LRC timestamped lyrics to preview timed lines, copy the full lyrics export text with a suggested `.txt` or `.lrc` filename, copy a bounded lyrics share excerpt, edit lyrics later, or delete them from the same dialog. Folder import also attaches matching sidecar lyrics such as `Song.lrc` or `Song.txt` beside `Song.mp3`, preferring LRC when both exist. Saved lyrics are included in Library, playlist, and custom smart playlist searches. While a track is playing, use the lyrics button in the player bar to open now-playing lyrics; LRC lines highlight and scroll with playback, and saved lyrics can be copied as timestamp-free share text from the sheet header.

## Backup and restore

Open the Options tab and choose **Export backup** to view a versioned JSON backup. Choose **Restore backup** and paste a backup JSON to replace the local library, playlists, lyrics, listening history, saved history views, submitted search history, pause-listening-history preference, theme and accent preferences, offline mode, queued offline media requests, podcast feed subscriptions, podcast refresh state, and podcast episode progress with that backup. Backups preserve queue metadata and local cache paths, not copied media bytes.

## Sleep timer

Tap the moon icon in the top-right corner and choose a preset duration, choose **Custom duration** and enter 1 to 1440 minutes, or choose **Stop at end of current track**. Turn on **Fade out before stopping** and choose a 10-second, 30-second, 1-minute, or 2-minute fade duration for timed sleep timers. Playback stops automatically when the timer or selected track ends.

## Options

The Options tab contains playback settings such as shuffle and repeat mode plus a **Theme** selector for System, Light, Dark, or AMOLED and an **Accent color** selector with persisted swatches. Turn on **Pause listening history** to stop new plays and resume progress from being stored until the toggle is turned off. Turn on **Offline mode** to pause network-backed source searches, feed refreshes, and saved stream playback from every player surface while keeping local file playback available. The Offline queue section shows provider-approved cache/download requests, lets you pause or resume queued requests, lets you cache queued direct media URLs into private app storage with post-write checksum verification, resumes retried direct HTTP(S) cache writes from saved `.part` bytes when the server supports Range requests, export verified cached media to a user-chosen folder, shows private cache usage, lets you set the private cache limit from 50 MB to 50 GB, lets you set per-provider private cache quotas for queued providers, and lets you trim the private cache to the app limit, clear cached media, remove one item, or clear the queue. After successful cache writes, AetherTune automatically evicts the oldest private cached files when usage exceeds a provider quota or the app limit. AetherTune restores those playback settings, pause-listening-history preference, theme and accent preferences, offline mode, offline cache limits, cache metadata, paused queue state, and the offline queue when you reopen the app.

## Provider plugins

The Sources tab explains the provider model and shows capability/privacy disclosure for enabled adapters. When offline mode is on, network-backed source searches, feed refreshes, and stream playback actions are paused; saved stream-only tracks are also blocked by the player until offline mode is turned off. Use the offline-media menu beside source results to queue a cache or download request; eligibility is gated by each provider's declared capabilities and privacy disclosure. The Options tab can pause/resume approved queue entries, cache direct media URLs into private app storage with stored byte-count/checksum metadata, retry interrupted direct HTTP(S) cache writes from saved `.part` files, export verified cached files to a user-chosen folder, set app/provider private cache limits, and trim or clear those private cache files later. Background download jobs are still roadmap work. The current app includes:

- Provider search: search the local library and enabled legal adapters together with typo-tolerant result scoring, then play playable results, save any result to the local library, or queue provider-approved cache/download requests. In offline mode, provider search shows local library results only and avoids network providers.
- Local Files: working.
- Demo Provider: template with declared search capability and no network access.
- Podcast RSS: add a legal RSS feed URL in Sources, import/export OPML, then refresh, play, resume, save, queue/cache checksum-verified eligible feed enclosures with direct HTTP(S) retry resume, trim/clear private cached media, set provider cache quotas, or remove feed episodes. Background download jobs remain roadmap work.
- Radio Browser: AetherTune discovers a public Radio Browser API mirror with fallback to the bundled default, searches public internet radio stations in Sources, filters by country/language/tag/codec/bitrate, validates selected station stream reachability, then plays a station or saves it to the local library; station plays are reported to Radio Browser's click endpoint. Live radio streams do not declare cache/download eligibility.
- Internet Archive: search public archive audio in Sources, filter by collection/subject/creator/year, apply returned facet chips, then play a resolved audio file, save it to the local library, or queue/cache checksum-verified public files with direct HTTP(S) retry resume; multi-file archive items appear as separate playable results and private cached media can be quota-limited, trimmed, or cleared in Options. Background download jobs remain roadmap work.
- Jellyfin: adapter foundation exists for API-key audio search and stream resolution against user-owned libraries; settings UI and secure credential storage remain roadmap work.
- Navidrome/Subsonic: adapter foundation exists for authenticated Subsonic REST search and stream resolution against user-owned servers; settings UI and secure credential storage remain roadmap work.
- More self-hosted/open providers: roadmap.
- Commercial services: official APIs only.
