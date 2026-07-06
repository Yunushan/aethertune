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

## Favorites

Open a track menu and choose **Favorite**. Use the heart button in the search bar to filter favorites.

## Queue controls

When you play a track from the library, the current filtered list becomes the queue. Use previous/next controls in the player bar.

## Sleep timer

Tap the moon icon in the top-right corner and choose a duration. Playback stops automatically when the timer ends.

## Options

The Options tab contains playback settings such as shuffle and repeat mode.

## Provider plugins

The Sources tab explains the provider model. The current app includes:

- Local Files: working.
- Demo Provider: template.
- Self-hosted/open providers: roadmap.
- Commercial services: official APIs only.
