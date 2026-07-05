# Feature Matrix

This matrix is intentionally honest. AetherTune is free/open-source and GitHub-ready, but it does not falsely claim every feature from every existing app is already production-complete.

Legend:

- **Done**: implemented in this scaffold.
- **Scaffolded**: architecture/interface exists; adapter or UI expansion needed.
- **Roadmap**: planned and documented.
- **Not included**: intentionally excluded for legal/privacy reasons.

## Core app features

| Feature | Status | Notes |
|---|---:|---|
| Android/iOS app shell | Done | Flutter app with Material 3 UI. |
| MIT license | Done | Root `LICENSE`. |
| No telemetry | Done | No analytics SDK or tracking dependency. |
| Local audio import | Done | Native file picker. |
| Local playback | Done | `just_audio` local file playback. |
| Stream URL playback | Done | Player supports URL-based streams when legal providers return URLs. |
| Library persistence | Done | `shared_preferences` JSON store. |
| Search | Done | Local title/artist/album search. |
| Favorites | Done | Toggle and filter favorites. |
| Queue | Done | Current list can be played as queue. |
| Next/previous | Done | Queue navigation. |
| Sleep timer | Done | 5/15/30/60/90 minute timer. |
| Shuffle | Done | `just_audio` shuffle flag. |
| Repeat one/all/off | Done | `just_audio` loop mode. |
| Provider plugin contract | Done | `MusicSourceProvider`. |
| Demo provider | Done | Metadata-only template provider. |
| Release workflow | Done | GitHub Actions scaffold. |

## Music-client feature targets

| Feature family | Status | Inspired by app categories |
|---|---:|---|
| YouTube Music-style search/home/charts | Scaffolded | Requires legal provider adapter. |
| Background audio service | Roadmap | Add `audio_service` integration and platform permissions. |
| Android notification controls | Roadmap | Build through `audio_service`. |
| Android Auto | Roadmap | Requires media browser service and testing in car emulator/device. |
| iOS Control Center / lock screen | Roadmap | Requires audio session and Now Playing metadata. |
| CarPlay | Roadmap | Requires Apple entitlement and extra app review requirements. |
| Offline cache manager | Roadmap | Add download queue, cache size limits, source permissions. |
| Manual playlists | Roadmap | Add playlist table/store. |
| Smart playlists | Roadmap | Add rules engine. |
| Synced lyrics | Roadmap | Add LRC parser and provider field. |
| Plain lyrics | Roadmap | Add lyrics repository and display. |
| Equalizer | Roadmap | Platform-specific; Android easier than iOS. |
| Pitch/tempo | Roadmap | Requires DSP/audio backend support. |
| Skip silence | Roadmap | Requires audio analysis or backend support. |
| Crossfade | Roadmap | Requires multi-player overlap or backend support. |
| Metadata editing | Roadmap | Local file tag writer required. |
| Folder browsing | Roadmap | File permission and scoped storage handling required. |
| Backup/restore | Roadmap | Export/import library JSON. |
| Multi-source subscriptions | Roadmap | Creator/channel/podcast/provider subscription model. |
| Self-hosted music | Scaffolded | Add Jellyfin/Navidrome/Subsonic adapter. |
| Podcasts | Scaffolded | Add RSS adapter. |
| Radio | Scaffolded | Add Radio Browser or similar open catalog adapter. |
| Internet Archive | Scaffolded | Add archive.org metadata and file resolver. |
| Commercial music services | Not included by default | Only official/documented APIs are acceptable. |
| DRM bypass | Not included | Out of scope. |
| Paid-service cloning | Not included | Out of scope. |
| Private API scraping | Not included | Out of scope. |

## Existing app inspiration map

| Existing app named by user | AetherTune design takeaway |
|---|---|
| Kreate / OpenTune / InnerTune / OuterTune / ViTune / RiMusic / MetroList | Clean YouTube Music-style UI, background playback, cache, lyrics, sleep timer, Android integrations. |
| SimpMusic / NouTube | Music + video/podcast-style source organization. |
| ArchiveTune | Archive/open-catalog-first provider idea. |
| Spotube | Separate metadata providers from playback providers. |
| Echo Music / Bloomee Tunes | Extension/provider-based architecture. |
| Namida | Strong local library and beautiful player UX. |
| PipePipe / NewPipe / LibreTube | Privacy-first browsing, no forced Google account, background audio. |
| Musify / Gyawun Music / Music You / Muzza / SoundPod / Harmony Music / Flow | Lightweight music-first mobile experience. |
| Grayjay | Multi-source subscriptions and creator following. |
| YMusic | YouTube-audio-oriented UX idea; no closed-source APK behavior copied. |
| YouTube Music official | Polished library/discovery UX; proprietary/paid/DRM features are not cloned. |

## Definition of “100% free/open-source”

AetherTune can be 100% free and open-source because its code, docs, and license are open. That is different from claiming 100% parity with proprietary or unofficial apps. Source adapters must also be free/open-source and legal before they can be merged into the core repository.
