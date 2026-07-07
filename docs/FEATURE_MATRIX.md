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
| Local audio import | Done | Native file picker. | Folder watch, recursive import, scoped storage UX. |
| Local playback | Done | `just_audio` local file playback. | Background service, notification controls, codec matrix. |
| Stream URL playback | Done | Player accepts legal direct stream URLs. | Provider resolver UI, retries, caching, auth headers. |
| Library persistence | Done | `shared_preferences` JSON store. | SQLite/Drift schema and migrations. |
| Backup/restore | Done | Versioned JSON export/restore UI plus store tests. | File-based import/export and migration tooling. |
| Search | Done | Local title/artist/album/genre filtering. | Global multi-provider search and ranking. |
| Recently added / library sort | Done | Store sort modes, Library sort menu, and unit coverage. | More smart filters and saved views. |
| Favorites | Done | Toggle and filter favorites. | Sync, smart filters, import/export. |
| Queue | Done | Current list can be played, restored across app launches, reordered, trimmed, and saved as a playlist. | Cross-device queue sync. |
| Recently played / listening history | Done | Persisted playback history with History tab and play counts. | Advanced stats, export filters, recap UI. |
| Manual playlists | Done | Persisted user playlists with add/remove/find/reorder/import/export/play UI. | Artwork and sync. |
| Built-in smart playlists | Done | Playlists tab exposes dynamic Favorites, Recently added, Recently played, and Most played collections. | Custom rule builder, sync, and artwork. |
| Plain/LRC lyrics | Done | Persisted per-track lyrics editor with LRC timestamp parsing, preview, and playback-linked highlighting/autoscroll. | Provider lyrics, file import/export, and sharing. |
| Next/previous | Done | Queue navigation. | Media key and lock-screen integration. |
| Sleep timer | Done | 5/15/30/60/90 minute presets, custom 1-1440 minute duration, and end-of-current-track mode. | Fade-out. |
| Shuffle | Done | `just_audio` shuffle flag is persisted across app launches. | Queue-aware shuffle polish. |
| Repeat one/all/off | Done | `just_audio` loop mode is persisted across app launches. | UI tests and platform media-session integration. |
| Provider plugin contract | Done | `MusicSourceProvider` requires capability flags and privacy/network disclosure. | Stable provider SDK, packaging, sandbox rules. |
| Demo provider | Done | Metadata-only provider template. | Real providers listed below. |
| Podcast RSS subscriptions | Scaffolded | Sources tab adds/removes persisted RSS feed subscriptions, imports/exports OPML, loads playable episodes, plays/saves episodes, includes backups, and provider parsing has tests. | Episode progress, refresh policy, and offline cache. |
| Radio Browser station search | Scaffolded | Sources tab searches Radio Browser, plays public streams, saves stations to the library, and provider parsing has tests. | Mirror discovery, station click accounting, richer browse filters, stream validation, and cache policy. |
| CI proof gates | Done | Flutter analyze/test, desktop builds, server analyze/test/compile, and tag/manual release artifact workflow. | Integration tests. |

## Full Parity Feature Surface

### Playback And Audio Engine

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Background audio | Roadmap | YouTube Music, InnerTune, RiMusic, NewPipe, YMusic | `audio_service`, platform permissions, integration tests. |
| Notification controls | Roadmap | YouTube Music, Namida, MetroList | Android media notification and metadata updates. |
| Lock-screen controls | Roadmap | YouTube Music, Namida | iOS/Android Now Playing metadata. |
| Media keys | Roadmap | Desktop players, Namida | Desktop keyboard/media session support. |
| Gapless playback | Roadmap | Namida, YouTube Music | Audio engine configuration and tests. |
| Crossfade | Roadmap | Namida, YouTube Music | Multi-player overlap or backend crossfade support. |
| ReplayGain / loudness normalization | Roadmap | Namida, local music players | Metadata scanner and gain application. |
| Equalizer | Roadmap | Namida, Musify, RiMusic | Platform-specific DSP layer. |
| Bass boost / virtualizer | Roadmap | Android music clients | Android DSP support and fallback behavior. |
| Pitch / tempo control | Roadmap | Podcast/video clients | DSP backend and UI controls. |
| Skip silence | Roadmap | Podcast/music clients | Audio analysis or playback backend support. |
| Audio-only mode for video sources | Blocked / official-only | YouTube Music, YMusic | Only through official APIs or user-provided legal streams. |
| Sleep timer with fade/custom rules | Scaffolded | InnerTune, Namida, YouTube Music | Custom duration and end-of-track action are done; fade-out still needs implementation. |
| Output device picker | Roadmap | YouTube Music, desktop players | Platform route picker and Bluetooth/cast support. |

### Library And Local Files

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local file import | Done | Namida, Musify | Folder and recursive import. |
| Folder browsing | Scaffolded | Namida, local music players | Imported-track folder groups are implemented; recursive folder tree UI and platform permissions remain. |
| Metadata scanner | Roadmap | Namida | Tag parser, artwork extraction, background indexing. |
| Metadata editing | Roadmap | Namida | Safe tag writer and rollback handling. |
| Duplicate resolver | Roadmap | Local library apps | Fingerprint/path/hash matching. |
| Album/artist/genre/source/folder views | Done | YouTube Music, Namida | Library browse sheets group tracks by artist, album, genre, source, and imported folder; metadata scanner still needs richer tags. |
| Recently added / recently played | Done | YouTube Music, Namida | Recently added sorting/API and recently played history are done; richer filters still needed. |
| Listening history | Done | YouTube Music, Last.fm-style clients | Export filters, privacy controls, and richer history search. |
| Stats / recap | Scaffolded | YouTube Music | Play counts are done; aggregation jobs and recap UI still needed. |
| Backup/restore | Done | Namida, local-first apps | File picker integration, cloud targets, migration checks. |
| Cross-device library sync | Roadmap | YouTube Music, Grayjay-style multi-device needs | Server auth, sync API, conflict handling. |

### Search, Discovery, And Recommendations

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local library search | Done | All music apps | Searches title, artist, album, and genre; advanced filters and typo tolerance remain. |
| Multi-provider search | Scaffolded | Spotube, Grayjay, Echo Music | Provider registry, query fan-out, ranking, errors. |
| Search suggestions | Roadmap | YouTube Music | Provider suggestions and local history. |
| Home feed | Roadmap | YouTube Music, InnerTune, RiMusic | Feed sections from legal providers. |
| Charts / trending | Roadmap | YouTube Music, OpenTune-style clients | Provider-backed chart adapters. |
| Mood/activity mixes | Roadmap | YouTube Music | Curated or provider-backed collections. |
| Artist radio / track radio | Roadmap | YouTube Music, InnerTune | Recommendation provider and queue generator. |
| Personalized recommendations | Roadmap | YouTube Music | Local preference model or official provider APIs. |
| Similar artists/albums | Roadmap | YouTube Music | Metadata provider and browse UI. |
| Concert alerts / artist updates | Roadmap | YouTube Music | Official/event provider integration. |

### Playlists And Queue Management

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Current queue playback | Done | All music apps | Cross-device queue sync and richer queue actions. |
| Manual playlists | Done | All music apps | Artwork and sync. |
| Smart playlists | Scaffolded | Namida, desktop players | Built-in dynamic playlists for favorites, recently added, recently played, and most played are implemented; user-created rules and synced dynamic queries remain. |
| Collaborative/shared playlists | Roadmap | YouTube Music | Server sync and permissions. |
| Playlist import/export | Done | Spotube, YouTube Music migration needs | JSON, M3U, and CSV import/export are implemented for tracks already in the local library. |
| Find in playlist | Done | YouTube Music | Search box filters playlist tracks by title, artist, or album while preserving playlist order. |
| Save queue as playlist | Done | Common player feature | Bulk queue actions and sync. |
| Radio queue generation | Roadmap | YouTube Music, RiMusic | Seed-based queue builder. |

### Lyrics

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Plain lyrics | Done | YouTube Music, InnerTune, Namida | Provider-backed lyrics, richer display, sharing. |
| Synced LRC lyrics | Done | InnerTune, RiMusic, Namida | LRC parser, timestamped editor preview, and playback-linked now-playing highlighting/autoscroll are implemented; provider LRC fetching remains separate. |
| Lyrics search | Roadmap | YouTube Music | Official/open lyrics provider. |
| Offline lyrics cache | Roadmap | InnerTune, Namida | Cache store and invalidation. |
| Lyrics sharing cards | Roadmap | YouTube Music | Rendered share image and permissions. |
| Manual lyrics import/edit | Scaffolded | Local library players | Manual editor is implemented; file import/association still needed. |

### Offline, Cache, And Downloads

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local offline playback | Done | Local music apps | Better file indexing. |
| Stream cache | Roadmap | InnerTune, RiMusic, YouTube Music | Cache manager and source permissions. |
| Download queue | Roadmap | YouTube Music, NewPipe | Legal download support only. |
| Cache size limits | Roadmap | All offline clients | Storage settings and eviction policy. |
| Per-provider offline policy | Scaffolded | Spotube, Grayjay | Provider capability flags and privacy disclosure are implemented; cache/download enforcement still needs implementation. |
| Offline mode toggle | Roadmap | YouTube Music | Network gate and offline-only UI. |
| Partial/resumable downloads | Roadmap | NewPipe-style clients | Downloader with resume and checksum support. |

### Providers And Sources

| Source/provider | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Local files | Done | Namida, Musify | Folder scanner and metadata parser. |
| Demo provider | Done | Provider template | Developer docs and test fixture provider. |
| Jellyfin | Roadmap | Self-hosted music users | Auth, library browse, stream resolver, tests. |
| Navidrome/Subsonic | Roadmap | Self-hosted music users | Subsonic API adapter and sync model. |
| Podcast RSS | Scaffolded | YouTube Music podcasts, NewPipe | RSS parser/provider, persisted feed subscriptions, OPML import/export, episode listing, playback, library save, and backup/restore are implemented; episode progress, refresh policy, and cache remain. |
| Radio Browser / internet radio | Scaffolded | Radio apps | Station search, playback, library save, provider parser, and playable station model are implemented; mirror discovery, click accounting, richer browse filters, stream validation, and cache policy remain. |
| Internet Archive | Roadmap | ArchiveTune | Metadata search, file resolver, collection browse. |
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
| Share track/album/playlist | Roadmap | All music apps | Deep links and export cards. |
| Comments/community posts | Not included by default | YouTube-style platforms | Moderation burden; official APIs only if ever supported. |

### Platform Integrations

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Android notification controls | Roadmap | YouTube Music, InnerTune, Namida | `audio_service`, manifest, notification tests. |
| Android Auto | Roadmap | YouTube Music, local music players | Media browser service and car emulator/device tests. |
| Android widgets / shortcuts | Roadmap | Music apps | Home screen widgets and shortcuts. |
| Android scoped storage polish | Roadmap | Local library apps | Permissions flow and folder grants. |
| iOS Control Center | Roadmap | YouTube Music | Now Playing integration. |
| iOS lock screen metadata | Roadmap | YouTube Music | Media item metadata and artwork. |
| iOS background audio | Roadmap | YouTube Music | Audio session config and App Store review notes. |
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
| Library sync | Roadmap | YouTube Music / multi-device needs | Conflict resolution and encrypted transport. |
| Playback position sync | Roadmap | Podcasts/video apps | Per-item progress model. |
| Playlist sync | Roadmap | Music services | Server playlist API. |
| Provider credential vault | Roadmap | Self-hosted/official APIs | Secure token storage and refresh. |
| Admin/ops endpoints | Roadmap | Server deployments | Metrics without user tracking, logs, health. |
| Federation/self-hosting docs | Roadmap | Open-source server users | Docker, systemd, reverse proxy, TLS docs. |

### UI, UX, Accessibility, And Customization

| Feature | Status | Inspired by | Needed to add |
|---|---:|---|---|
| Material 3 shell | Done | Music You, modern Android apps | Full design system. |
| Mini player / full player | Scaffolded | All music apps | Full-screen now-playing view and gestures. |
| Desktop responsive layout | Roadmap | Desktop players | Split panes, resizable sidebars, keyboard focus. |
| Themes | Roadmap | Music You, RiMusic | Dynamic color, dark/light, custom accent. |
| AMOLED theme | Roadmap | Android music apps | Theme variant. |
| Artwork-dominant player | Roadmap | Namida, YouTube Music | Player redesign and animated transitions. |
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
| Provider permission model | Done | Providers declare capabilities and privacy-sensitive behaviors through `MusicSourceProvider`; Sources tab displays the disclosure. |
| Network request disclosure | Done | `ProviderPrivacyDisclosure` lists contacted domains and data sent for each adapter. |
| Secure token storage | Roadmap | Required before account/provider auth. |
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
| Provider contract test suite | Roadmap | Shared tests each provider must pass. |
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
| ArchiveTune | Internet Archive search, metadata, playable public files. | Roadmap |
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
| RiMusic | YouTube Music-style playback, cache, lyrics, Android polish. | Roadmap / official-only |
| Harmony Music | Lightweight music client UX and provider ideas. | Roadmap |
| YMusic | YouTube-audio-oriented UX. | Roadmap / official-only |
| YouTube Music | Official music/video streaming UX, recommendations, radio, podcasts, downloads, profiles. | Roadmap / official-only |
| Flow | Lightweight music-first user experience. | Roadmap |
| MetroList | Clean music player/library UX. | Roadmap |

## Minimum Build Plan To Reach Real 100% Implemented Parity

1. Replace JSON preferences with a real local database and migrations.
2. Build full local library: folders, metadata scanner, metadata editing, duplicate resolver, playlists, backup/restore.
3. Add `audio_service` and platform media sessions for background playback, notifications, lock screen, media keys, and Android Auto/CarPlay where allowed.
4. Build provider SDK v1 with capability declarations, network disclosure, auth handling, and contract tests.
5. Implement legal providers: local folder scanner, feed-managed Podcast RSS, full Radio Browser UX, Jellyfin, Navidrome/Subsonic, Internet Archive.
6. Add official-only adapters where terms allow: Spotify metadata, YouTube/YouTube Music, SoundCloud, Bandcamp, or others.
7. Build offline cache/download manager with per-provider legal capability checks.
8. Add lyrics: plain text, synced LRC, cache, search, manual import/edit.
9. Add discovery: home feed, charts, recommendations, moods, artist/track radio, similar artists.
10. Add video surfaces only through legal providers: video player, PiP, captions, chapters, subscriptions.
11. Build server auth, sync, provider credential vault, playlist/library/playback-position APIs, and self-hosting docs.
12. Polish desktop: responsive layout, tray/menu bar, global hotkeys, installers, signing.
13. Harden release artifacts with signing, notarization, installers, and store-ready packaging.
14. Add accessibility, localization, golden tests, integration tests, provider tests, dependency audits, and privacy/network audits.

## Definition of "100% free/open-source"

AetherTune can be 100% free and open-source because its code, docs, and license are open. That is different from claiming 100% parity with proprietary or unofficial apps. Source adapters must also be free/open-source and legal before they can be merged into the core repository.
