# Changelog

## 0.1.0

Initial GitHub-ready scaffold.

- Added MIT license.
- Added Flutter client app source.
- Added local file import.
- Added local/URL playback controller.
- Added queue, favorites, search, sleep timer, shuffle, repeat.
- Added local search suggestions from submitted query history, playback history, and library metadata.
- Added provider offline cache/download policy gates with Podcast RSS and Internet Archive allow rules plus Radio Browser live-stream denial.
- Added persisted offline mode to pause network-backed source search, feed refresh, and stream playback actions.
- Added stored track metadata editing for title, artist, album, and genre.
- Added duplicate track detection and merge handling for local library entries.
- Added custom smart playlists with search, favorite, play-count, sort, and limit rules.
- Added playlist artwork URL editing, display, export/import, and backup restore.
- Added local listening stats recap for tracks, artists, albums, genres, and listening time.
- Added listening stats date ranges and JSON/CSV export.
- Added optional sleep timer fade-out during the final 30 seconds before playback stops.
- Added provider plugin contract.
- Added provider capability flags and privacy/network disclosure metadata.
- Added unified provider search fan-out with ranking and per-provider error reporting.
- Added Podcast RSS parser/provider foundation for legal audio feeds.
- Added Radio Browser parser/provider foundation for public internet radio.
- Added Sources-tab Radio Browser station search with play and save actions.
- Added Radio Browser station click accounting on playback.
- Added Radio Browser country, language, tag, codec, and bitrate search filters.
- Added Radio Browser mirror discovery with fallback to the bundled default mirror.
- Added Internet Archive public audio search with playable file resolution.
- Added Internet Archive collection, subject, creator, and year filters with multi-file item results.
- Added persisted Podcast RSS feed subscriptions with episode play/save actions.
- Added Podcast RSS OPML import/export for feed migration.
- Added Podcast RSS episode progress/resume persistence.
- Added Podcast RSS refresh status tracking and stale-feed policy.
- Added README, docs, CI, issue templates, contribution docs.
- Added Flutter desktop wrapper generation and desktop CI build gates.
- Added Dart server package with health, info, catalog endpoints, and tests.
