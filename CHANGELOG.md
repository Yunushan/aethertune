# Changelog

## Unreleased

- Added generated Flutter localization catalogs for English, Turkish, and Arabic, covering the app shell, responsive navigation, and first-run onboarding with RTL Arabic layout support.
- Added transactional local M4A title, artist, album, genre, and PNG/JPEG embedded-cover writing for standard tail- and front-metadata layouts. Front-loaded files safely repair validated `stco`/`co64` media offsets, while malformed or fragmented layouts are refused before mutation.
- Improved player accessibility with spoken compact-player seek values and semantic previous/next artwork actions for assistive technologies.

- Added active offline cache/download cancellation: pausing or removing an in-progress request now stops its foreground HTTP transfer, keeps resumable private `.part` bytes, and preserves the correct paused queue state instead of recording a false failure.
- Added local track artwork editing: validated private PNG/JPEG/GIF/WebP picks, safe web URLs, scanned-artwork restore, scanner-refresh preservation, and portable backup/sync/playlist privacy fallback.
- Added persisted local artist following from artist browse sheets, a newest-followed-artists Home feed section, and backup/snapshot-sync coverage; remote creator/channel subscriptions remain roadmap work.
- Added paginated Internet Archive audio search with explicit continuation, exhaustion, retry-safe result retention, and provider pagination tests.
- Documented and tested portable snapshot restoration for manual playlists and valid playback progress, while keeping automatic merge and collaboration as future work.
- Added persistent watched audio folders: recursive imports now monitor relevant audio and sidecar-lyrics changes with debounced rescans, safe incomplete-scan handling, user-state preservation, and Options refresh/remove controls.
- Added persisted 0.5x-3x playback-speed controls in Now Playing and Options, with system-media state propagation and player/widget contract coverage.
- Documented the implemented optional self-hosted cross-device library snapshot sync, including secure-token configuration, checksum verification, explicit conflict resolution, and its intentionally excluded device-local state.
- Added atomic test-before-replace credential rotation for Jellyfin and Navidrome/Subsonic with confirmation UI, secure-vault rollback, old/new secret redaction, metadata-editor isolation, private artwork invalidation, and position-preserving active queue re-resolution that stops unresolved tracks.
- Added capability-gated remote playlist creation, rename, deletion, track append, removal, and reordering for Jellyfin and Navidrome/Subsonic using documented APIs, credential-redacted failures, offline gating, refreshed catalog state, exact request fixtures, and phone widget flows.
- Added a bounded private local-file bridge that publishes validated Jellyfin/Navidrome/Subsonic artwork to Android notifications and Apple lock-screen/Control Center metadata without persisting authenticated URLs or runtime file URIs; includes atomic writes, format-aware hashed paths, stale-part cleanup, account-scoped deletion, and system-media/serialization/cache tests.
- Added credential-safe Jellyfin/Navidrome/Subsonic artwork for catalog rows, saved library tiles, the mini-player, and Now Playing using safe persisted image IDs, authenticated binary byte loaders, image MIME/10 MiB gates, bounded memory caching, and account invalidation tests; upgraded Subsonic requests from reversible password encoding to random-salt authentication tokens.
- Added responsive Jellyfin and Navidrome/Subsonic Artists, Albums, Tracks, and Playlists browsing with filtering, drill-down, play/save/offline-queue actions, retry/empty states, endpoint fixtures, phone/desktop widget coverage, and offline zero-request enforcement.
- Added Sources-tab Jellyfin and Navidrome/Subsonic account setup with connection testing, HTTPS-by-default validation, platform-secure credential storage, redacted failures, provider-search activation, runtime-only authenticated playback URLs, restart reconstruction, and account removal cleanup.
- Added basic M4A title, artist, album, and genre metadata atom parsing during recursive folder scans.
- Added basic FLAC Vorbis comment title, artist, album, and genre parsing during recursive folder scans.
- Added basic ID3v2 MP3 title, artist, album, and genre text-frame parsing during recursive folder scans.
- Added paused offline cache/download queue state with Options-tab pause/resume controls, persisted backup support, and batch caching that skips paused requests.

## 0.1.0

Initial GitHub-ready scaffold.

- Added MIT license.
- Added Flutter client app source.
- Added local file import.
- Added local/URL playback controller.
- Added queue, favorites, search, sleep timer, shuffle, repeat.
- Added persisted system/light/dark/AMOLED theme preference.
- Added local search suggestions from submitted query history, playback history, and library metadata.
- Added provider offline cache/download policy gates with Podcast RSS and Internet Archive allow rules plus Radio Browser live-stream denial.
- Added persisted offline cache/download queue with Sources-tab provider actions and Options-tab queue management.
- Added user-triggered offline cache storage for provider-approved direct media URLs.
- Added resumable HTTP Range retries for direct-URL offline cache writes using private `.part` files.
- Added private offline cache usage reporting plus trim/clear eviction controls.
- Added configurable private offline cache size limits with backup/restore persistence.
- Added automatic private cache pressure eviction after successful cache writes.
- Added per-provider private cache quotas for provider-approved offline media.
- Added cached media byte-count/checksum metadata with post-write checksum verification.
- Added user-chosen folder export for verified private cached media.
- Added persisted offline mode to pause network-backed source search, feed refresh, and player-wide saved stream playback actions.
- Added a local-files-only library filter for offline-ready browsing.
- Added recursive local folder scanning/import for supported audio files.
- Added stored track metadata editing for title, artist, album, and genre.
- Added local folder filename metadata parsing for track numbers and artist-title names.
- Added basic ID3v1 MP3 title, artist, and album metadata parsing during folder scans.
- Added duplicate track detection and merge handling for local library entries.
- Added local Home feed sections for continue listening, recent plays, radio seeds, most played, favorites, and recently added tracks.
- Added local charts for top tracks, artists, albums, and genres by playback range.
- Added local Home recommendations and mood/activity mixes from library metadata and playback signals.
- Added similar local tracks from shared artist, album, genre, and library activity signals.
- Added privacy-safe local share text for tracks, library browse groups, and manual playlists.
- Added bounded lyrics excerpt share text for saved and draft plain/LRC lyrics.
- Added UTF-8 TXT/LRC lyrics file import in the lyrics editor.
- Added copyable TXT/LRC lyrics export text with suggested filenames.
- Added local saved-lyrics search for library, playlist, and smart playlist queries.
- Added a desktop-width navigation rail for the Flutter app shell.
- Added custom smart playlists with search, favorite, play-count, sort, and limit rules.
- Added local seed-based track radio queues from library metadata, favorites, and play history.
- Added playlist artwork URL editing, display, export/import, and backup restore.
- Added local listening stats recap for tracks, artists, albums, genres, and listening time.
- Added listening stats date ranges and JSON/CSV export.
- Added optional sleep timer fade-out during the final 30 seconds before playback stops.
- Added provider plugin contract.
- Added provider capability flags and privacy/network disclosure metadata.
- Added unified provider search fan-out with ranking and per-provider error reporting.
- Added local library results to unified provider search, including offline-mode local-only search.
- Added typo-tolerant local library, playlist, saved-lyrics, suggestion, and provider search scoring.
- Added Podcast RSS parser/provider foundation for legal audio feeds.
- Added Radio Browser parser/provider foundation for public internet radio.
- Added Sources-tab Radio Browser station search with play and save actions.
- Added Radio Browser station click accounting on playback.
- Added Radio Browser country, language, tag, codec, and bitrate search filters.
- Added Radio Browser mirror discovery with fallback to the bundled default mirror.
- Added Radio Browser station stream validation before playback/save decisions.
- Added Internet Archive public audio search with playable file resolution.
- Added Internet Archive collection, subject, creator, and year filters with multi-file item results.
- Added Internet Archive collection, subject, creator, and year facet suggestion chips.
- Added Jellyfin provider foundation for API-key audio search and stream resolution against user-owned libraries.
- Added Navidrome/Subsonic provider foundation for authenticated Subsonic REST search and stream resolution.
- Added shared provider contract tests for current source adapters.
- Added persisted Podcast RSS feed subscriptions with episode play/save actions.
- Added Podcast RSS OPML import/export for feed migration.
- Added Podcast RSS episode progress/resume persistence.
- Added Podcast RSS refresh status tracking and stale-feed policy.
- Added README platform overview picture plus Android, iOS, Windows, macOS, Linux, server, and animated tour media.
- Added README, docs, CI, issue templates, contribution docs.
- Added Flutter desktop wrapper generation and desktop CI build gates.
- Added Dart server package with health, info, catalog endpoints, and tests.
