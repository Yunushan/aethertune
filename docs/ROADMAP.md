# Roadmap

## 0.1.x: Foundation

- [x] Flutter mobile shell
- [x] Flutter desktop build support
- [x] Dart server foundation
- [x] MIT license
- [x] Local import
- [x] Local playback
- [x] Local Home feed sections
- [x] Local charts by playback range
- [x] Local mood/activity mixes
- [x] Personalized local recommendations
- [x] Similar local tracks
- [x] Listening history
- [x] Queue
- [x] Queue reorder/remove
- [x] Persistent queue
- [x] Save queue as playlist
- [x] Local seed-based track radio queues
- [x] Local share text for tracks, browse groups, and playlists
- [x] Persist shuffle/repeat settings
- [x] Favorites
- [x] Manual playlists
- [x] Plain lyrics editor
- [x] TXT/LRC lyrics file import
- [x] Local lyrics excerpt share text
- [x] JSON backup/restore
- [x] Sleep timer
- [x] Custom sleep timer duration
- [x] End-of-track sleep timer
- [x] Optional sleep timer fade-out
- [x] Adjustable sleep timer fade duration
- [x] Provider interface
- [ ] More unit tests
- [ ] UI polish

## 0.2.x: Library

- [x] Manual playlists
- [x] Playlist reorder
- [x] Find in playlist
- [x] Playlist import/export JSON/M3U/CSV
- [x] Built-in smart playlists
- [x] Custom rule smart playlists
- [ ] Nested smart playlist rule builder
- [x] Playlist artwork URL display/editing
- [ ] Playlist artwork picker, cropper, generated collage, and sync
- [x] Backup/restore JSON
- [x] Imported-track folder browse
- [x] Recursive folder import
- [ ] Recursive folder browser
- [x] Filename metadata scanner
- [x] Basic ID3v1 MP3 metadata scanner
- [x] Basic ID3v2 MP3 text metadata scanner
- [x] Basic FLAC Vorbis comment metadata scanner
- [x] Basic M4A metadata atom scanner
- [ ] Rich embedded audio tag scanner
- [x] Stored metadata editor
- [x] Duplicate resolver scaffold
- [x] File-hash duplicate matching
- [ ] Audio fingerprint duplicate matching
- [x] Recently played
- [x] Local play counts
- [x] Local stats recap
- [x] Stats date ranges and export
- [ ] Yearly/monthly recap cards and richer visualizations
- [x] Recently added view
- [x] Local search suggestions
- [x] Persisted search query history
- [x] Artist/album/genre/source browse
- [x] Similar local track browser

## 0.3.x: Platform audio

- [ ] Android notification controls
- [ ] Android Auto
- [ ] iOS lock screen controls
- [ ] iOS background audio session
- [ ] Desktop media key support
- [x] Desktop navigation rail at wide widths
- [ ] Split-pane desktop layout polish

## 0.4.x: Server foundation

- [x] Server health endpoint
- [x] Server info endpoint
- [x] Server catalog endpoint
- [ ] Auth model
- [ ] Library sync API
- [ ] Remote provider coordination

## 0.5.x: Open providers

- [x] Provider capability and privacy disclosure contract
- [x] Per-provider cache/download policy gate
- [x] Unified provider search fan-out, ranking, and error reporting
- [x] Podcast RSS parser/provider foundation
- [x] Podcast RSS feed subscriptions and episode UI
- [x] Podcast OPML import/export
- [x] Podcast episode progress/resume
- [x] Podcast refresh policy
- [x] Podcast RSS cache/download policy declarations
- [x] Podcast offline cache/download queue
- [x] Podcast direct enclosure private cache storage
- [ ] Podcast background download jobs
- [x] Radio Browser parser/provider foundation
- [x] Radio Browser station search/play/save UI
- [x] Radio Browser station click accounting
- [x] Radio Browser richer browse filters
- [x] Radio Browser mirror discovery
- [x] Radio Browser live-stream cache/download denial policy
- [x] Radio Browser stream validation
- [x] Internet Archive audio search/provider foundation
- [x] Internet Archive collection, subject, creator, and year search filters
- [x] Internet Archive multi-file item result expansion
- [x] Internet Archive offline/download policy declarations
- [x] Internet Archive cache/download queue
- [x] Internet Archive direct file private cache storage
- [x] Internet Archive facet suggestion UI and collection filter chips
- [ ] Internet Archive dedicated collection detail pages
- [x] Jellyfin provider foundation
- [ ] Jellyfin settings UI and secure credential storage
- [x] Navidrome/Subsonic provider foundation
- [ ] Navidrome/Subsonic settings UI and secure credential storage

## 0.6.x: Offline and lyrics

- [x] Offline mode toggle
- [x] Player-wide saved stream blocking while offline mode is enabled
- [x] Local-files-only library filter for offline-ready browsing
- [x] Per-provider cache/download policy gate
- [x] Cache/download queue manager
- [x] Download queue
- [x] Offline queue pause/resume controls
- [x] User-triggered direct URL offline cache storage
- [x] Cached media byte-count/checksum metadata
- [x] Post-write checksum verification for private cached media
- [x] User-chosen folder export for verified private cached media
- [x] Private cache usage and eviction controls
- [x] Manual private cache trim/clear controls
- [x] Configurable cache size limits
- [x] Automatic private cache pressure eviction
- [x] Per-provider private cache quotas
- [x] Resumable direct URL cache retries
- [ ] Background offline downloader jobs
- [x] Plain lyrics display/edit
- [x] LRC parser and timestamp preview
- [x] Playback-synced lyric highlighting
- [ ] Lyrics provider/search/cache

## 1.0.0: Stable

- [ ] Stable provider SDK
- [x] Release artifact workflow
- [ ] Fully signed/notarized release process
- [x] Persisted system/light/dark/AMOLED theme preference
- [x] Custom accent color picker
- [ ] Material You dynamic platform color
- [ ] Accessibility pass
- [ ] Localization setup
