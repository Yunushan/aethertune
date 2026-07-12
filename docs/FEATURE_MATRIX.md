# Feature Matrix

This matrix is intentionally honest. AetherTune can be 100% free/open-source, but it is not yet 100% feature-complete against every app named below. This document defines the complete parity target and separates what is already real from what still needs implementation.

Reference apps named by the user:

Kreate, OpenTune, InnerTune, SimpMusic, ArchiveTune, Spotube, Echo Music, Namida, PipePipe, NewPipe, LibreTube, Musify, AuraMusic, Bloomee Tunes, Gyawun Music, Music You, Muzza, SoundPod, NouTube, Grayjay, OuterTune, ViTune, RiMusic, Harmony Music, YMusic, YouTube Music, Flow, and MetroList.

## Status Legend

- **Done**: implemented in code, documented, and covered by a relevant check where practical.
- **Scaffolded**: architecture or placeholder exists, but the user-facing feature is not complete.
- **Roadmap**: planned here, but no meaningful implementation exists yet.
- **Blocked / official-only**: possible only through user-owned data, open catalogs, or official/legal APIs.
- **Not included**: intentionally excluded for privacy, legal, platform-policy, or safety reasons.

## What "100% Coverage" Means

For this project, "100% coverage" means the matrix covers the full feature surface needed to compete with the named apps. It does not mean every feature is already implemented.

To claim 100% implemented parity later, AetherTune must satisfy all of these gates:

| Gate | Required evidence |
|---|---|
| Feature exists | User-facing code path, not just documentation. |
| Cross-platform behavior | Verified on every supported target that claims the feature. |
| Provider legality | Uses local files, user-owned servers, open catalogs, public feeds, or official APIs. |
| Tests/checks | Unit, widget, integration, build, or workflow evidence matching the feature risk. |
| Documentation | User guide, release notes, and support notes updated. |
| Failure handling | Clear empty, loading, error, offline, and permission states. |
| Accessibility | Keyboard, screen reader, contrast, reduced motion, and touch target checks where applicable. |
| Privacy | No hidden telemetry, credential leakage, private API scraping, or DRM bypass. |

## Implemented Foundation

| Feature | Status | Current evidence | Needed for full parity |
|---|---:|---|---|
| Android/iOS app shell | Done | Flutter app with Material 3 UI. | Store signing, background modes, platform polish. |
| Linux/macOS/Windows desktop build | Done | CI builds debug desktop targets. | Desktop-first layout, installers, update channel. |
| Server package | Done | Dart HTTP service under `services/server`. | Auth, sync, provider coordination, deployment docs. |
| Server health/info/catalog endpoints | Done | Covered by server tests and CI compile gate. | Real persisted catalog and authenticated APIs. |
| MIT license | Done | Root `LICENSE`. | Third-party notice automation. |
| No telemetry | Done | No analytics SDK or tracking dependency. | Privacy tests and network-call audit. |
| Local audio import | Done | Native file picker plus recursive folder scanner for supported audio extensions, including filename track-number parsing, artist/title parsing, basic ID3v1 MP3 title/artist/album tag parsing, basic ID3v2 MP3 title/artist/album/genre text-frame and APIC/PIC artwork parsing, basic FLAC Vorbis comment title/artist/album/genre and picture artwork parsing, basic M4A title/artist/album/genre atom plus `covr` artwork parsing, basic WAV RIFF INFO title/artist/album/genre parsing, and matching `.lrc`/`.txt` lyric sidecar import with scanner tests. Track rows and the player bar render local/provider artwork with a fallback icon. | Folder watch, scoped storage UX, richer embedded tag parsing, tag writing, and artwork editing. |
| Local playback | Done | `just_audio` local file playback uses one lazy native playlist; Android/iOS/macOS use native plugin backends, Linux/Windows bundle initialized MediaKit audio backends, and Android/iOS/macOS wrap playback in a queue-aware system media session. | Physical-device codec and lifecycle matrix. |
| Stream URL playback | Done | Player accepts legal direct stream URLs. | Provider resolver UI, retries, caching, auth headers. |
| Library persistence | Done | `shared_preferences` JSON store. | SQLite/Drift schema and migrations. |
| Backup/restore | Done | Versioned JSON export/restore UI plus store tests, including theme/accent preferences, pause-listening-history preference, offline mode, and queued offline media requests. | File-based import/export and migration tooling. |
| Stored metadata editing | Scaffolded | Track menus edit saved title, artist, album, and genre, with store tests for persistence/search/browse/suggestions. | Audio tag writer, artwork editing, scanner reconciliation, and rollback handling. |
| Duplicate resolver | Scaffolded | Options tab finds duplicate library tracks by normalized local path, scanner content hash, provider/external ID, stream URL, or metadata plus known duration, then merges the selected keeper while preserving playlists, favorites, lyrics, history, and progress; scanner/store tests cover content hashes, detection, and persistence. | Audio fingerprinting, scanner reconciliation, batch review UI, and undo. |
| Search | Done | Typo-tolerant local title/artist/album/genre/source/folder/saved-lyrics filtering plus submitted-query/playback/metadata suggestion chips and Sources-tab provider search fan-out/ranking with local-library merge and configured Jellyfin/Navidrome/Subsonic accounts. | Pagination and richer global ranking. |
| Recently added / library sort | Done | Store sort modes, Library sort menu, and unit coverage. | More smart filters and saved views. |
| Favorites | Done | Toggle and filter favorites. | Sync, smart filters, import/export. |
| Queue | Done | Current list is loaded once as a native playlist, follows automatic engine index transitions, restores across app launches, preserves current position while reordered/trimmed, filters stream entries in offline mode, and can be saved as a playlist. Credential-bearing self-hosted URLs are runtime-only, stripped from snapshots, reconstructed from secure storage after restart, removed with their provider account, and stripped/re-resolved after credential rotation. Rotation stops the loaded queue before replacement, preserves position/play state on success, and leaves unresolved current tracks metadata-only and stopped. Controller tests cover those boundaries plus native transitions, mutation rebuilds, persistence, and stop-at-end isolation. | Cross-device queue sync. |
| Recently played / listening history | Done | Persisted playback history with History tab, typo-tolerant search over recently played tracks and per-play entries, persisted named range/query views with create/apply/update/rename/delete UI and backup coverage, per-play entry deletion, play counts, estimated listening time, date-range filters, monthly/yearly calendar recap cards, saveable PNG recap visuals, JSON/CSV stats export, top track/artist/album/genre recap, clear action, and a persisted pause-listening-history toggle that stops new play/progress writes while preserving existing history until cleared. | Cross-device view sync. |
| Manual playlists | Done | Persisted user playlists with add/remove/find/reorder/import/export/play UI plus playlist artwork URL display/editing in the list and playlist sheet. Store tests cover artwork persistence, clear, JSON export/import, and backup restore. | Local gallery/file picker, cropper, generated collage artwork, and sync. |
| Smart playlists | Scaffolded | Playlists tab exposes built-in dynamic Favorites, Recently added, Recently played, and Most played collections plus persisted custom smart playlists with search text, favorites-only, minimum play count, sort mode, and result limit rules. Store tests cover rule matching, persistence, update/delete, and backup restore. | Rich nested rule builder, sync, artwork, and cross-device dynamic queries. |
| Plain/LRC lyrics | Done | Persisted per-track lyrics editor with LRC timestamp parsing, preview, playback-linked highlighting/autoscroll, UTF-8 file import, matching folder-scan sidecar import, user-triggered LRCLIB plain/synced search, attributed local caching, and copyable TXT/LRC export text with suggested filenames. | Native file-save export, more provider adapters, and richer sharing. |
| Next/previous | Done | Queue navigation. | Media key and lock-screen integration. |
| Sleep timer | Done | 5/15/30/60/90 minute presets, custom 1-1440 minute duration, end-of-current-track mode, optional 10-second/30-second/1-minute/2-minute fade-out, and unit coverage for timer/fade rules. | Platform media-session integration. |
| Shuffle | Done | `just_audio` shuffle flag is persisted across app launches. | Queue-aware shuffle polish. |
| Repeat one/all/off | Done | `just_audio` loop mode is persisted across app launches. | UI tests and platform media-session integration. |
| Provider plugin contract | Done | `MusicSourceProvider` requires capability flags, privacy/network disclosure, and cache/download policy inputs. | Stable provider SDK, packaging, sandbox rules. |
| Demo provider | Done | Metadata-only provider template. | Real providers listed below. |
| Podcast RSS subscriptions | Scaffolded | Sources tab adds/removes persisted RSS feed subscriptions, imports/exports OPML, loads playable episodes, tracks refresh status/staleness, plays/saves episodes, queues cache/download requests after provider policy approval, materializes direct enclosure URLs into checksum-verified private cache storage with HTTP Range retry resume, usage/app-provider quota eviction controls, resumes saved episode progress, includes backups, declares cache/download policy for legal enclosures, and provider/cache/store behavior has tests. | Background download jobs. |
| Radio Browser station search | Scaffolded | Sources tab searches Radio Browser, discovers a public API mirror before default searches with fallback to the bundled mirror, filters by country/language/tag/codec/bitrate, validates selected station stream reachability/content type, plays public streams, sends station click accounting on playback, saves stations to the library, denies cache/download policy for live streams, and provider parsing/filter/mirror/validation/click behavior has tests. | Deeper codec probing, retry/backoff policy, and richer station detail pages. |
| Internet Archive audio search | Scaffolded | Sources tab searches public Internet Archive audio, filters by collection/subject/creator/year, exposes returned collection/subject/creator/year facet chips, expands multi-file items into separate playable tracks, resolves file URLs, plays/saves tracks, queues cache/download requests after provider policy approval, materializes direct public file URLs into checksum-verified private cache storage with HTTP Range retry resume, usage/app-provider quota eviction controls, declares cache/download policy for public files, and provider/cache/search/filter behavior has tests. | Dedicated collection detail pages and background download jobs. |
| Offline mode | Done | Options tab has a persisted offline mode that pauses network-backed provider search, feed refresh, Sources playback actions, and player-wide saved URL stream playback; Library has a local-files-only offline-ready filter; backup/restore, source classification, offline playback policy, direct URL cache materialization/manual eviction, checksum metadata, HTTP Range retry resume for direct URL cache writes, automatic cache pressure eviction, app/provider cache limits, and library filter tests cover behavior. | Background downloader jobs. |
| CI proof gates | Done | Flutter analyze/test, Android and unsigned iOS compilation, desktop builds, server analyze/test/compile, generated secure-storage entitlement/config tests, and tag/manual release artifact workflow. | Physical-device integration tests. |

## Full Parity Feature Surface

### Playback And Audio Engine

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Background audio | Scaffolded | YouTube Music, InnerTune, RiMusic, NewPipe, YMusic | Android/iOS/macOS initialize a music `AudioSession` and `audio_service` handler around the same native queue engine; generated Android/iOS wrappers receive validated foreground-service/background-audio settings, and CI compiles Android plus unsigned iOS apps. Needed next: physical-device interruption, route, battery, and process-lifecycle fixtures. |
| Notification controls | Scaffolded | YouTube Music, Namida, MetroList | Android declares the foreground media service and media-button receiver; the handler publishes queue/current item metadata, artwork, duration, position, buffering state, repeat/shuffle state, and previous/play-pause/next/stop actions. Unit tests prove state publication and command routing; physical notification/device tests remain. |
| Lock-screen controls | Scaffolded | YouTube Music, Namida | Android/iOS/macOS receive the current queue item, artwork, playback state, position, seek, repeat, shuffle, and transport callbacks through `audio_service`. Needed next: physical Android/iOS lock-screen and Control Center fixtures. |
| Media keys | Scaffolded | Desktop players, Namida | macOS receives `audio_service` system transport callbacks; Android/iOS headset/media buttons use the same handler. Windows/Linux global media-key integration and physical-host tests remain. |
| Gapless playback | Scaffolded | Namida, YouTube Music | Queue playback now uses a lazy `ConcatenatingAudioSource` instead of per-track reloads; automatic native index transitions update app state without replacing the source, repeat stays in the engine, controller tests prove the no-reload contract, and MediaKit playlist prefetch is enabled for bundled Linux/Windows backends. Needed next: acoustic transition fixtures on physical Android/iOS/macOS devices and Windows/Linux audio hosts before a universal zero-gap claim. |
| Crossfade | Roadmap | Namida, YouTube Music | Multi-player overlap or backend crossfade support. |
| ReplayGain / loudness normalization | Roadmap | Namida, local music players | Metadata scanner and gain application. |
| Equalizer | Roadmap | Namida, Musify, RiMusic | Platform-specific DSP layer. |
| Bass boost / virtualizer | Roadmap | Android music clients | Android DSP support and fallback behavior. |
| Pitch / tempo control | Roadmap | Podcast/video clients | DSP backend and UI controls. |
| Skip silence | Roadmap | Podcast/music clients | Audio analysis or playback backend support. |
| Audio-only mode for video sources | Blocked / official-only | YouTube Music, YMusic | Only through official APIs or user-provided legal streams. |
| Playback speed | Done | NewPipe, PipePipe, LibreTube, podcast and music players | The shared audio engine supports 0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x, 2.5x, and 3x playback. Now Playing and Options expose the same setting; it persists across launches and is republished to supported system media sessions. Pitch-preserving DSP and per-track speed rules remain future work. |
| Sleep timer with fade/custom rules | Done | InnerTune, Namida, YouTube Music | Presets, custom 1-1440 minute duration, end-of-current-track action, opt-in 10-second/30-second/1-minute/2-minute fade-out, volume restore on cancel/stop, and unit-tested fade timing/volume rules are implemented. Needed next: media-session-aware sleep timer notifications. |
| Output device picker | Roadmap | YouTube Music, desktop players | Platform route picker and Bluetooth/cast support. |

### Library And Local Files

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local file import | Done | Namida, Musify | File picker import and recursive folder scanning are implemented, including common filename metadata parsing, basic ID3v1 MP3 tag parsing, basic ID3v2 MP3 text-frame and APIC/PIC artwork parsing, basic FLAC Vorbis comment and picture artwork parsing, basic M4A metadata atom plus `covr` artwork parsing, and basic WAV RIFF INFO tag parsing. Folder imports persist a watched root that resyncs relevant filesystem changes while the app runs and when it opens; richer tag formats and scoped-storage polish remain. |
| Folder browsing | Scaffolded | Namida, local music players | Imported-track flat folder groups, recursive folder import, recursive folder tree browsing with aggregate parent counts, descendant playback queues, privacy-safe folder share text, and persisted watched roots are implemented. Where the platform filesystem supports monitoring, watched folders debounce relevant audio/lyrics changes, rescan safely on startup and refresh, preserve favorites/added timestamps for stable local IDs, and avoid deletion after incomplete scans. Platform storage permission polish remains. |
| Metadata scanner | Scaffolded | Namida | Folder import derives album/folder metadata from parent folders, parses common filename patterns such as leading track numbers and `Artist - Title`, reads basic ID3v1 MP3 title/artist/album tags, reads basic ID3v2 MP3 title/artist/album/genre text frames and APIC/PIC artwork, reads basic FLAC Vorbis comment title/artist/album/genre tags and picture artwork, reads basic M4A title/artist/album/genre metadata atoms plus `covr` artwork, and reads basic WAV RIFF INFO title/artist/album/genre tags before falling back to filenames. Watched folders reconcile changed content hashes and new/deleted files while retaining user state and never overwrite existing manual/provider lyrics with a sidecar. Scanner/watcher tests cover recursive import, relevant-event filtering, debounce, sidecars, incomplete-scan deletion protection, dashed titles, ID3v1/ID3v2/FLAC/M4A/WAV tag preference, UTF-16 ID3v2 text, partial tag merges, artwork extraction, and tag fallback. Needed next: background indexing, richer tag formats, and safe tag writing. |
| Metadata editing | Scaffolded | Namida | Track menus edit persisted library title, artist, album, and genre; search, browse groups, suggestions, playlists, and backup data update from the edited record, with store tests. Needed next: safe audio tag writer, artwork editing, scanner reconciliation, and rollback handling. |
| Duplicate resolver | Scaffolded | Local library apps | Options duplicate resolver detects path, scanner content hash, provider item, stream URL, and metadata plus known-duration matches, then merges the selected keeper with playlists/history/lyrics/progress preserved. Needed next: audio fingerprinting, scanner reconciliation, batch review UI, and undo. |
| Album/artist/genre/source/folder views | Done | YouTube Music, Namida | Library browse sheets group tracks by artist, album, genre, source, and imported folder; metadata scanner now reads basic ID3v2 MP3, FLAC Vorbis, M4A, and WAV RIFF INFO genre text plus embedded MP3/FLAC/M4A artwork. Richer tag formats and album-level artwork grouping remain. |
| Recently added / recently played | Done | YouTube Music, Namida | Recently added sorting/API and recently played history are done; recently played lists can be searched by track metadata and saved lyrics, and named history range/query views persist across restarts and backups. Saved recently-added filter presets remain. |
| Listening history | Done | YouTube Music, Last.fm-style clients | Playback history, range exports, clear history, per-play entry deletion, typo-tolerant history search, and pause-listening-history privacy control are implemented. |
| Stats / recap | Scaffolded | YouTube Music, Namida | Store-level stats aggregate local tracks, favorites, play counts, estimated listening duration, and top tracks/artists/albums/genres; Home and History show responsive normalized bar charts for top tracks/artists; History filters stats by all time, last 7 days, last 30 days, or last year, persists named range/query views, shows monthly/yearly calendar recap cards, exports each recap as a fixed-size PNG through the native save dialog, exports the selected range as JSON/CSV, supports deleting individual play entries, searches history, and respects the pause-listening-history toggle. Store/widget tests cover ranking, saved-view persistence/backup, chart normalization/compact layout, date filtering, calendar recaps, PNG rendering, exports, pause behavior, entry deletion, and history search. Needed next: calendar heatmaps, more chart dimensions, and saved recap themes. |
| Backup/restore | Done | Namida, local-first apps | Includes local library data, theme/accent preferences, pause-listening-history preference, offline mode, and queued offline media requests; file picker integration, cloud targets, migration checks remain. |
| Cross-device library sync | Done | YouTube Music, Grayjay-style multi-device needs | An optional self-hosted server stores an authenticated, checksum-verified versioned library snapshot. The app keeps the bearer token in secure storage, tests configuration before saving, uploads/downloads explicitly, preserves device-local paths and cache settings on restore, and requires a choice on revision conflict. Automatic scheduling, merge, queue sync, and cross-device provider credentials remain out of scope. |

### Search, Discovery, And Recommendations

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local library search | Done | All music apps | Searches title, artist, album, genre, source, folder, and locally saved plain/LRC lyric text with typo-tolerant term matching; advanced filters and richer global ranking remain. |
| Multi-provider search | Scaffolded | Spotube, Grayjay, Echo Music | `ProviderSearchCoordinator` fans out to searchable adapters, ranks mixed results with typo-tolerant metadata scoring, limits per-provider results, resolves metadata-only tracks when supported, captures provider-specific errors, has unit tests, and Sources can search the Local Library, Demo Provider, Radio Browser, Internet Archive, and configured Jellyfin/Navidrome/Subsonic accounts together. Configured self-hosted accounts also expose dedicated Artists, Albums, and Playlists tabs with filtering, drill-down, and credential-safe in-app artwork. Offline mode keeps all provider requests local-library-only. Needed next: provider pagination, richer provider-specific ranking, and browse surfaces for the remaining providers. |
| Search suggestions | Scaffolded | YouTube Music | Library tab suggestion chips come from persisted submitted query history, recent playback, title, artist, album, genre, source, and folder metadata, including typo-tolerant local matching; store tests cover history dedupe, persistence, backup restore, and matching. Needed next: provider suggestions and remote suggestions. |
| Home feed | Scaffolded | YouTube Music, InnerTune, RiMusic | Local Home tab builds local recommendations, mood/activity mixes, continue-listening, recently played, radio seed, most played, favorites, recently added, and local charts sections from the on-device library. Needed next: provider-backed feed sections, pagination, refresh controls, and account/provider personalization where legal. |
| Charts / trending | Scaffolded | YouTube Music, OpenTune-style clients | Local charts rank top tracks, artists, albums, and genres for all time, last 7 days, last 30 days, or last year from playback history; responsive normalized top-track/top-artist bar charts are visible on Home and History with compact-layout widget coverage. Needed next: provider-backed chart adapters, trending feeds, region/language filters, and public chart refresh policies. |
| Mood/activity mixes | Scaffolded | YouTube Music | Local Focus, Energy, Chill, Workout, and Sleep mixes are generated from playable library metadata, favorites, play counts, and recency and shown on Home when matching tracks exist. Needed next: provider-curated moods, richer audio-feature metadata, regional editorial collections, and saved/generated mix pages. |
| Artist radio / track radio | Scaffolded | YouTube Music, InnerTune | Local seed track radio queues match playable library tracks by artist, genre, or album, then rank them with favorites and play history from every track menu; Home also suggests radio seeds with local matches. Needed next: provider-backed recommendations, artist pages, and remote radio seeds. |
| Personalized recommendations | Scaffolded | YouTube Music | Home shows local "For you" recommendations by weighting favorites and recent playback across artist, album, and genre metadata while skipping just-played tracks. Needed next: provider-backed recommendations, user controls for taste signals, explainability, and cross-device personalization. |
| Similar artists/albums | Scaffolded | YouTube Music | Track menus open a local Similar tracks sheet that ranks playable library matches by shared artist, album, and genre, boosts favorites/play history, explains match reasons, and can play the result queue. Needed next: provider-backed artist/album pages, similar artist graphs, album recommendations, and remote metadata enrichment where legal. |
| Concert alerts / artist updates | Roadmap | YouTube Music | Official/event provider integration. |

### Playlists And Queue Management

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Current queue playback | Done | All music apps | Cross-device queue sync and richer queue actions. |
| Manual playlists | Done | All music apps | Local artwork picker/cropper, generated artwork collages, and sync. |
| Smart playlists | Scaffolded | Namida, desktop players | Built-in dynamic playlists plus persisted user-created smart rules are implemented for metadata/lyrics search text, favorites-only, minimum play count, sort mode, and result limit. Needed next: nested rule builder, artwork, sync, and shared dynamic queries. |
| Playlist artwork | Scaffolded | YouTube Music, Namida, RiMusic | Manual playlist menu accepts or clears http/https artwork URLs; playlist cards and sheets render artwork with a stable fallback; AetherTune JSON exports/imports and full backups preserve the artwork URI. Needed next: local picker/cropper, generated collages from tracks, image cache policy, and cross-device sync. |
| Collaborative/shared playlists | Roadmap | YouTube Music | Server sync and permissions. |
| Playlist import/export | Done | Spotube, YouTube Music migration needs | JSON, M3U, and CSV import/export are implemented for tracks already in the local library. |
| Find in playlist | Done | YouTube Music | Search box filters playlist tracks by title, artist, album, or locally saved lyrics while preserving playlist order. |
| Save queue as playlist | Done | Common player feature | Bulk queue actions and sync. |
| Radio queue generation | Scaffolded | YouTube Music, RiMusic | Local seed-based queue builder is implemented for playable library tracks and starts playback with the seed first. Needed next: provider recommendation adapters, richer ranking, and saved/generated radio playlists. |

### Lyrics

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Plain lyrics | Done | YouTube Music, InnerTune, Namida | Manual plain lyrics, UTF-8 `.txt` import, matching `.txt` folder-scan sidecar import, LRCLIB plain-result selection, attributed local persistence, copyable `.txt` export text, local search, and attributed share excerpts are implemented. Needed next: native file-save export, richer display, and more provider adapters. |
| Synced LRC lyrics | Done | InnerTune, RiMusic, Namida | LRC parser, timestamped editor preview, playback-linked now-playing highlighting/autoscroll, UTF-8 `.lrc` import, matching `.lrc` folder-scan sidecar import, LRCLIB synced-result selection, attributed local persistence, and copyable `.lrc` export text are implemented. |
| Lyrics search | Done | YouTube Music | The editor opens an explicit LRCLIB search sheet, discloses the contacted domain and metadata sent, uses the documented unauthenticated `/api/search` endpoint with an identifying User-Agent, ranks up to 20 plain/synced results locally by title/artist/album/duration, handles loading/empty/error/retry/instrumental states, blocks network search in offline mode, and stores only the selected result with provider ID/name/record/URL attribution. Provider, widget, model, store, restart, backup, merge, and share paths are covered; upstream pagination and more provider adapters remain future extensions. |
| Offline lyrics cache | Roadmap | InnerTune, Namida | Cache store and invalidation. |
| Lyrics sharing cards | Scaffolded | YouTube Music | Lyrics editor and now-playing lyrics sheets can copy a bounded AetherTune lyrics excerpt from saved or draft plain/LRC lyrics, stripping LRC timestamps and limiting shared lines by default. Needed next: rendered image cards, selected-line ranges, platform share sheets, artwork backgrounds, rights-aware provider permissions, and deep links. |
| Manual lyrics import/edit | Scaffolded | Local library players | Manual editor imports UTF-8 `.txt` and `.lrc` files through the platform file picker, folder scans automatically associate matching basename `.lrc` or `.txt` sidecars without overwriting existing saved lyrics, previews parsed synced LRC lines, saves/deletes per-track lyrics, can select attributed plain/synced LRCLIB results, copies full TXT/LRC export text with suggested filenames, and copies bounded attributed share excerpts. Needed next: native file-save export, embedded tag import, and batch matching. |

### Offline, Cache, And Downloads

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local offline playback | Done | Local music apps | Better file indexing. |
| Stream cache | Scaffolded | InnerTune, RiMusic, YouTube Music | Provider-approved cache requests can be queued, paused/resumed, managed, downloaded into private app storage for direct HTTP(S) media URLs, resumed from private `.part` files with HTTP Range requests on retry, checksum-verified after write, stored with byte-count/checksum metadata, exported to a user-chosen folder after verification, measured, trimmed/cleared to configurable app/provider size limits, automatically evicted after cache writes when over limit, and replayed as local files. Background fetch jobs remain. |
| Download queue | Scaffolded | YouTube Music, NewPipe | Sources tab queues legal downloads only after `OfflineMediaPolicy` allows them, persists the queue with cache metadata and paused state, exposes remove/clear/cache/export/pause/resume management in Options, materializes direct URLs into checksum-verified private storage with HTTP Range retry resume, can export verified cached files to a user-chosen folder, and can evict private cached files. Background jobs and system Downloads integration remain. |
| Cache size limits | Done | All offline clients | Options can measure private cache usage, set a persisted 50-51200 MB private cache limit, set persisted per-provider quotas for queued providers, trim private cache files to the app limit, clear cached media, automatically evict the oldest private cached files after successful cache writes when usage exceeds a provider quota or the app limit, and preserve limits through backup/restore. | More provider-specific default policies. |
| Per-provider offline policy | Done | Spotube, Grayjay | `OfflineMediaPolicy` allows local files, permits Podcast RSS and Internet Archive cache/download only when providers declare capability plus disclosure, denies live Radio Browser streams, and has unit coverage through provider contract/coordinator tests. |
| Offline mode toggle | Done | YouTube Music | Persisted Options toggle pauses network-backed Sources searches, feed refreshes, Sources stream playback actions, and player-wide saved URL stream playback; backup/restore preserves it, Library can filter to local offline-ready files, and Options exposes the offline queue/cache manager with usage/app-provider quota eviction controls, HTTP Range retry resume for direct URL cache writes, and automatic post-cache pressure eviction. Needed next: background download jobs. |
| Partial/resumable downloads | Scaffolded | NewPipe-style clients | Default direct HTTP(S) cache writes resume from existing private `.part` files with Range requests and still verify the final byte count/checksum; queued requests can be paused/resumed before processing. Needed next: background workers, in-progress cancellation, provider-supplied checksum manifests, and system Downloads integration. |

### Providers And Sources

| Source/provider | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local files | Done | Namida, Musify | Recursive folder scanner, filename metadata parser, matching `.lrc`/`.txt` lyric sidecar association, basic ID3v1 MP3 title/artist/album tag parser, basic ID3v2 MP3 title/artist/album/genre text-frame and APIC/PIC artwork parser, basic FLAC Vorbis comment title/artist/album/genre and picture artwork parser, basic M4A title/artist/album/genre atom plus `covr` artwork parser, basic WAV RIFF INFO title/artist/album/genre parser, and persisted watched-folder rescan are implemented; richer tag parsing and artwork editing remain. |
| Demo provider | Done | Provider template | Developer docs and test fixture provider. |
| Jellyfin | Scaffolded | Self-hosted music users | Sources can add/edit/test/remove HTTPS-by-default Jellyfin accounts, store API keys in the platform credential vault, activate authenticated audio search, and open dedicated Artists, Albums, and Playlists tabs. The account menu has a confirmed test-before-replace API-key rotation flow with vault rollback, redacted errors, artwork invalidation, and active queue re-resolution. Artist-to-album and album/playlist-to-track drill-down supports filtering, play all, save all, per-track playback/save, and provider-approved cache/download queueing. The separately declared playlist-editing capability exposes create/rename/delete, add from album tracks, and move/remove through ordered replacement using Jellyfin's documented playlist/library endpoints; guarded failures preserve the current catalog. Safe image IDs/tags persist with metadata; validated artwork renders through bounded in-memory/private-file caches in app and system media surfaces without exposing credential URLs. Exact read/write endpoints and bodies, duplicate/order preservation, input/no-op rules, secure store/cache/serialization/rotation, phone mutation flows, desktop no-overflow rendering, failure/retry, and offline zero-request behavior have tests. Needed next: cross-device sync. |
| Navidrome/Subsonic | Scaffolded | Self-hosted music users | Sources can add/edit/test/remove HTTPS-by-default Navidrome/Subsonic accounts, store passwords in the platform credential vault, activate `ping.view` testing plus `search3.view` search, and browse documented artist/album/playlist endpoints. The account menu has a confirmed test-before-replace password rotation flow with vault rollback, redacted errors, artwork invalidation, and active queue re-resolution. Every request uses random-salt `t=md5(password+salt)` instead of reversible `p=enc:` authentication. The separately declared playlist-editing capability exposes create/rename/delete, add from album tracks, and move/remove; `createPlaylist.view`, `updatePlaylist.view`, and `deletePlaylist.view` fixtures verify repeated ordered song IDs, duplicates, a fresh salt per write, and no `p` parameter. Credential-safe artwork renders through bounded in-memory/private-file caches in app and system media surfaces. Needed next: cross-device sync. |
| Podcast RSS | Scaffolded | YouTube Music podcasts, NewPipe | RSS parser/provider, persisted feed subscriptions, OPML import/export, refresh status/stale policy, episode listing, playback, saved episode progress/resume, library save, backup/restore, cache/download policy declarations, queued offline requests, checksum-verified private direct-enclosure caching with HTTP Range retry resume, and app/provider quota private cache eviction are implemented; background download jobs remain. |
| Radio Browser / internet radio | Scaffolded | Radio apps | Station search with country/language/tag/codec/bitrate filters, public API mirror discovery, fallback mirror behavior, selected stream validation, playback, station click accounting, library save, provider parser, playable station model, and live-stream cache/download denial are implemented; deeper codec probing and retry/backoff policy remain. |
| Internet Archive | Scaffolded | ArchiveTune | Public audio metadata search, collection/subject/creator/year filters, facet suggestion chips, playable file resolver, multi-file item results, Sources-tab play/save/cache/download queue, checksum-verified private direct-file caching with HTTP Range retry resume, app/provider quota private cache eviction, cache/download policy declarations, and provider/cache tests are implemented; dedicated collection detail pages and background download jobs remain. |
| Spotify metadata | Blocked / official-only | Spotube | Official API metadata only; playback must be legal/user-authorized. |
| YouTube / YouTube Music | Blocked / official-only | YouTube Music, InnerTune, NewPipe family | Official API, embeds, or user-provided legal URLs only; no private API scraping. |
| SoundCloud or similar services | Blocked / official-only | Multi-source clients | Official API or documented public feeds only. |
| Bandcamp / artist stores | Blocked / official-only | Open music discovery | Official/public pages only where terms allow. |
| User-added custom provider plugins | Roadmap | Echo Music, Bloomee Tunes, Grayjay | Plugin SDK, packaging, signing, sandbox, and provider contract test suite. |

### Video And Media Browsing

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Music video playback | Roadmap | YouTube Music, NewPipe, LibreTube | Legal video provider, player UI, PiP support. |
| Audio/video toggle | Blocked / official-only | YouTube Music | Only where provider terms allow. |
| Picture-in-picture | Roadmap | YouTube Music, NewPipe | Platform PiP APIs and tests. |
| Captions/subtitles | Roadmap | YouTube/NewPipe-style apps | Caption parser/provider support. |
| Chapters | Roadmap | YouTube/NewPipe-style apps | Chapter model and player markers. |
| Sponsor/segment skipping | Not included by default | Video clients | Could support user-owned/open segment data; no invasive tracking. |
| Channel/creator pages | Roadmap | Grayjay, NewPipe, LibreTube | Multi-source creator model. |
| Video comments | Not included by default | YouTube apps | High moderation/privacy cost; official APIs only if added. |

### Social, Subscriptions, And Multi-Source Feeds

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Provider subscriptions | Scaffolded | Grayjay, NewPipe, LibreTube | Podcast RSS feed subscriptions are persisted and removable; creator/channel subscriptions for video and multi-source feeds remain. |
| Creator/channel following | Roadmap | Grayjay, YouTube Music | Creator identity model and feed. |
| Multi-source unified feed | Roadmap | Grayjay | Feed merge, dedupe, ranking, filters. |
| Public profile | Roadmap | YouTube Music | Optional server account and privacy controls. |
| Taste-match/shared mixes | Roadmap | YouTube Music | Server-side sharing and opt-in profile model. |
| Share track/album/playlist | Scaffolded | All music apps | Track menus, album/artist/genre/source/folder browse sheets, and playlist menus copy local AetherTune share text for tracks, groups, and playlists; local file paths are redacted from share payloads; monthly/yearly listening recaps render and save as PNG cards. Needed next: native platform share sheets, deep links, track/album/playlist artwork cards, importable links, and server-backed public sharing. |
| Comments/community posts | Not included by default | YouTube-style platforms | Moderation burden; official APIs only if ever supported. |

### Platform Integrations

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Android notification controls | Scaffolded | YouTube Music, InnerTune, Namida | `SystemMediaPlaybackEngine` publishes queue metadata/artwork/playback state and handles transport, seek, repeat, and shuffle; authenticated provider artwork is exposed only through bounded private local files; bootstrap adds and validates wake-lock/foreground-media permissions, `AudioService`, and `MediaButtonReceiver`; CI compiles an APK and unit-tests the handler contract. Needed next: emulator/physical notification lifecycle tests. |
| Android Auto | Roadmap | YouTube Music, local music players | Media browser service and car emulator/device tests. |
| Android widgets / shortcuts | Roadmap | Music apps | Home screen widgets and shortcuts. |
| Android scoped storage polish | Roadmap | Local library apps | Permissions flow and folder grants. |
| iOS Control Center | Scaffolded | YouTube Music | `audio_service` receives queue metadata/artwork/playback state and transport/seek/repeat/shuffle callbacks, with authenticated provider artwork supplied through credential-free private local files; CI compiles an unsigned iOS app. Needed next: physical Control Center fixtures. |
| iOS lock screen metadata | Scaffolded | YouTube Music | Current title, artist, album, artwork, duration, position, queue index, and playback state are published as `MediaItem`/`PlaybackState`; physical lock-screen verification remains. |
| iOS background audio | Scaffolded | YouTube Music | Startup configures a music `AudioSession`, bootstrap adds `UIBackgroundModes: audio`, and the unsigned iOS CI build validates native integration. Needed next: physical interruption/route/background lifecycle tests and App Store review notes. |
| CarPlay | Roadmap | YouTube Music | Apple entitlement and CarPlay UI. |
| Linux desktop packaging | Roadmap | Desktop players | AppImage/Flatpak/deb workflow. |
| Windows packaging | Roadmap | Desktop players | MSIX/zip installer and signing. |
| macOS packaging | Roadmap | Desktop players | Notarization, dmg/pkg, signing. |
| Desktop tray / menu bar | Roadmap | Desktop players | Platform menu/tray plugin. |
| Global hotkeys | Roadmap | Desktop players | Platform-specific shortcut handling. |
| Cast / Chromecast | Roadmap | YouTube Music | Cast integration where legal/provider-supported. |
| Wear OS / watch controls | Roadmap | YouTube Music | Companion app or media session support. |

### Server, Sync, And Accounts

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Server health endpoint | Done | Production services | Deployment checks. |
| Server info endpoint | Done | Client compatibility | Versioned capabilities. |
| Server catalog endpoint | Done | API foundation | Persistence and auth. |
| Server executable compile | Done | Release readiness and release workflow server artifacts. | Deployment workflow. |
| Authentication | Roadmap | Sync services | Token model, secure storage, tests. |
| User profiles | Roadmap | YouTube Music | Optional account model. |
| Library sync | Done | YouTube Music / multi-device needs | The optional Dart server accepts authenticated `GET`/`PUT /api/v1/sync/library` snapshots with size checks, checksums, durable latest-revision storage, and optimistic conflict responses. The client requires HTTPS unless the user explicitly permits HTTP, stores its token securely, and exposes manual upload/download plus conflict resolution. Automatic sync, registration, token lifecycle, and merge remain roadmap work. |
| Playback position sync | Scaffolded | Podcasts/video apps | Local podcast episode progress/resume is implemented, and the manual authenticated library snapshot carries valid progress entries across devices with the rest of the portable library. Automatic background sync, per-item conflict merge, and video-specific state remain. |
| Playlist sync | Scaffolded | Music services | Manual playlists, ordered track IDs, and safe remote artwork URIs are included in the authenticated portable library snapshot and restore across devices. Automatic per-playlist merge, collaboration, provider credentials, and a dedicated server playlist API remain. |
| Provider credential vault | Scaffolded | Self-hosted/official APIs | Jellyfin API keys and Navidrome/Subsonic passwords use `flutter_secure_storage` across Android, iOS, Linux, macOS, and Windows; account metadata and safe artwork IDs are separate, secrets and credential-bearing media/artwork URLs are excluded from queue/library JSON and backups, Subsonic requests derive per-request salted tokens, and confirmed test-before-replace rotation rolls back failed vault writes before invalidating artwork and re-resolving active queues. Deletion removes vault entries and provider caches, Android backup is disabled, Apple keychain entitlements are generated, and Linux CI/release installs libsecret. Needed next: biometric policy choices, migration/versioning, and physical-device keychain/keystore/credential-manager tests. |
| Admin/ops endpoints | Roadmap | Server deployments | Metrics without user tracking, logs, health. |
| Federation/self-hosting docs | Roadmap | Open-source server users | Docker, systemd, reverse proxy, TLS docs. |

### UI, UX, Accessibility, And Customization

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Material 3 shell | Done | Music You, modern Android apps | Full design system. |
| Mini player / full player | Done | All music apps | The compact player now switches to a phone-safe control set below 720 px and opens a responsive full Now Playing route. The full route provides large artwork, live seek/elapsed/remaining time, queue position, favorite, lyrics, queue, shuffle, repeat, previous/play-pause/next controls, and left/right artwork swipe navigation; widget tests cover the full control contract, automatic queue transition, and a 390 px no-overflow mini player. More secondary actions can be added with future provider features. |
| Desktop responsive layout | Scaffolded | Desktop players | The Flutter shell switches from bottom navigation to a labeled, scrollable `NavigationRail` at desktop widths while preserving the player bar and tab state across Linux, macOS, and Windows builds; breakpoint behavior has unit coverage. Needed next: split panes, resizable sidebars, richer keyboard focus traversal, and desktop-specific density tuning. |
| Themes | Scaffolded | Music You, RiMusic | Options exposes persisted System, Light, Dark, AMOLED, and accent color swatch choices; the app shell switches `ThemeMode`, applies the selected Material seed color, backups preserve theme/accent preferences, and store/theme tests cover persistence, restore, and seed mapping. Needed next: Material You dynamic platform color and per-platform polish. |
| AMOLED theme | Scaffolded | Android music apps | AMOLED preference forces dark mode and uses black scaffold/canvas/navigation surfaces. Needed next: full component contrast audit and per-screen black-surface tuning. |
| Artwork-dominant player | Scaffolded | Namida, YouTube Music | The responsive full Now Playing route gives artwork up to 480 px the primary mobile/desktop visual position and keeps controls unframed beside or below it; artwork swipes navigate the queue. Animated shared-element transitions, palettes derived from artwork, and visualizer integration remain. |
| Visualizer | Roadmap | Namida-style polish | Audio analysis and render surface. |
| Accessibility pass | Roadmap | Required quality gate | Screen reader labels, focus order, contrast. |
| Localization | Roadmap | Global music apps | ARB/i18n pipeline and translations. |
| Onboarding | Roadmap | Consumer apps | First-run provider/local import flow. |
| Empty/error/loading states | Scaffolded | Required product quality | Standard state components and tests. |

### Privacy, Safety, And Legal Boundaries

| Feature/policy | Status | Notes |
|---|---:|---|
| No telemetry by default | Done | Keep analytics out unless explicit opt-in is ever added. |
| No DRM bypass | Not included | Will not be implemented. |
| No credential stealing | Not included | Will not be implemented. |
| No paid-service cloning | Not included | Will not be implemented. |
| No private API scraping | Not included | Use official/documented APIs, open feeds, or user-owned servers. |
| Provider permission model | Done | Providers declare capabilities and privacy-sensitive behaviors through `MusicSourceProvider`; Sources tab displays the disclosure and `OfflineMediaPolicy` gates cache/download eligibility. |
| Network request disclosure | Done | `ProviderPrivacyDisclosure` lists contacted domains and data sent for each adapter. |
| Pause listening history | Done | History and Options expose a persisted toggle that stops new playback-history and resume-progress writes; backup/restore preserves the preference. |
| Delete listening history entries | Done | The History tab lists individual play events for the selected range and can remove one event without clearing all history. |
| Secure token storage | Scaffolded | Implemented for static Jellyfin and Navidrome/Subsonic credentials through platform-secure storage with HTTPS default, explicit insecure-HTTP consent, redacted errors, no authenticated URL persistence, confirmed atomic rotation with rollback, and random-salt Subsonic request tokens that avoid transmitting the reversible encoded password. OAuth refresh tokens and physical-device storage tests remain. |
| Content policy/moderation | Roadmap | Required before public profiles, comments, or social surfaces. |

### Testing, Release, And Maintenance

| Feature | Status | Needed to add |
|---|---:|---|
| Flutter analyze/test CI | Done | Broader widget/integration tests. |
| Desktop build CI | Done | Release-mode packaging and smoke tests. |
| Server analyze/test/compile CI | Done | API integration tests and load tests. |
| Release artifact workflow | Done | Tag/manual workflow builds APK/AAB, desktop archives, and server binaries. | Signing, notarization, installers, and store packaging. |
| Signed releases | Roadmap | Android signing, macOS notarization, Windows signing. |
| SBOM / dependency audit | Roadmap | License and vulnerability scanning. |
| Golden UI tests | Roadmap | Stable screenshots for key views. |
| Provider contract test suite | Scaffolded | Shared capability/disclosure tests cover Demo, Podcast RSS, Radio Browser, Internet Archive, Jellyfin, and Navidrome/Subsonic; self-hosted tests additionally cover secure metadata/secret separation, connection testing, rejected rotation, failed-vault-write rollback, old/new secret redaction, successful provider reconstruction, memory/private artwork invalidation, ephemeral stream/artwork URL stripping, position-preserving active queue re-resolution, unresolved-track stopping, restart reconstruction, removal, exact browse/detail/artwork and playlist-write endpoints/bodies/query lists, input validation/no-op append, ordered duplicate IDs, fresh mutation salts, guarded mutation failure state, system-media publication, phone/desktop navigation, play/save/create/rename/delete/add/move/remove actions, retry, offline zero-request behavior, and native wrapper requirements. Dedicated LRCLIB tests cover its separate lyrics contract. Needed next: reusable fixture package, live opt-in integration fixtures, and CI reporting per adapter. |
| E2E smoke test | Roadmap | Launch app, import fixture, play fixture where possible. |
| Crash/error reporting | Roadmap | Local logs first; any remote reporting must be opt-in. |

## App-Inspiration Coverage Map

This table maps each named app to the AetherTune feature surface it implies. It is not a claim that the current app implements all of each app.

| App | Coverage target implied | Current status |
|---|---|---:|
| Kreate | YouTube Music-style discovery, background playback, cache, playlists, lyrics. | Roadmap |
| OpenTune | YouTube Music-style browse/search, lyrics, playlists, offline/cache. | Roadmap |
| InnerTune | YouTube Music client UX, background playback, cache, synced lyrics. | Roadmap |
| SimpMusic | Music/video source organization, online browse, player UX. | Roadmap |
| ArchiveTune | Internet Archive search, metadata, playable public files. | Scaffolded |
| Spotube | Metadata/playback provider separation, Spotify-style metadata. | Scaffolded / official-only |
| Echo Music | Extension/provider-based architecture. | Scaffolded |
| Namida | Strong local library, metadata, advanced player, stats, beautiful UX. | Roadmap |
| PipePipe | Privacy-first video/music browsing and subscriptions. | Roadmap / official-only |
| NewPipe | Video/music browsing, downloads where legal, subscriptions, background audio. | Roadmap / official-only |
| LibreTube | Privacy-first YouTube-style client concepts. | Roadmap / official-only |
| Musify | Lightweight music-first playback and local/simple online sources. | Roadmap |
| AuraMusic | Lightweight music-first UI and discovery ideas. | Roadmap |
| Bloomee Tunes | Multi-source/provider music experience. | Scaffolded |
| Gyawun Music | Lightweight mobile music UX. | Roadmap |
| Music You | Material You styling and Android-native polish. | Scaffolded |
| Muzza | Material mobile player ideas. | Roadmap |
| SoundPod | Lightweight streaming/player UX. | Roadmap |
| NouTube | Music/video source browsing. | Roadmap / official-only |
| Grayjay | Multi-source subscriptions, creator following, unified feeds. | Roadmap |
| OuterTune | YouTube Music-style client features. | Roadmap / official-only |
| ViTune | YouTube Music-style playback, cache, lyrics. | Roadmap / official-only |
| RiMusic | YouTube Music-style playback, cache, lyrics, Android polish. | Scaffolded / official-only |
| Harmony Music | Lightweight music client UX and provider ideas. | Roadmap |
| YMusic | YouTube-audio-oriented UX. | Roadmap / official-only |
| YouTube Music | Official music/video streaming UX, recommendations, radio, podcasts, downloads, profiles. | Roadmap / official-only |
| Flow | Lightweight music-first user experience. | Roadmap |
| MetroList | Clean music player/library UX. | Roadmap |

## Minimum Build Plan To Reach Real 100% Implemented Parity

1. Replace JSON preferences with a real local database and migrations.
2. Build full local library: recursive folder import, metadata scanner, metadata editing, duplicate resolver, playlists, backup/restore.
3. Extend the implemented Android/iOS/macOS `audio_service` media session with physical-device lifecycle fixtures, Windows/Linux global media keys, and Android Auto/CarPlay browsing where allowed.
4. Build provider SDK v1 with capability declarations, network disclosure, auth handling, and contract tests.
5. Complete legal providers: background Podcast RSS jobs, richer Radio Browser UX, self-hosted cross-device sync, and Internet Archive collection pages.
6. Add official-only adapters where terms allow: Spotify metadata, YouTube/YouTube Music, SoundCloud, Bandcamp, or others.
7. Expand the current checksum-verified direct-URL offline cache with HTTP Range retry resume, queue pause/resume, and user-chosen folder export into a full cache/download manager with background jobs, in-progress cancellation, provider checksum manifests where available, and deeper system Downloads integration where legally allowed.
8. Add lyrics: plain text, synced LRC, cache, search, manual import/edit.
9. Add discovery: home feed, charts, recommendations, moods, artist/track radio, similar artists.
10. Add video surfaces only through legal providers: video player, PiP, captions, chapters, subscriptions.
11. Extend the implemented static-credential vault with OAuth token refresh, biometric policy, and migration/versioning, then build automatic sync, per-item playlist/library/playback-position merge APIs, and self-hosting docs.
12. Polish desktop: responsive layout, tray/menu bar, global hotkeys, installers, signing.
13. Harden release artifacts with signing, notarization, installers, and store-ready packaging.
14. Add accessibility, localization, golden tests, integration tests, provider tests, dependency audits, and privacy/network audits.

## Definition of "100% free/open-source"

AetherTune can be 100% free and open-source because its code, docs, and license are open. That is different from claiming 100% parity with proprietary or unofficial apps. Source adapters must also be free/open-source and legal before they can be merged into the core repository.
