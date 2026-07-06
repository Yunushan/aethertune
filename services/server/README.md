# AetherTune Server

This is the Dart HTTP service for AetherTune server-side features.

```bash
dart pub get
dart run bin/server.dart
```

Available endpoints:

- `GET /health`
- `GET /api/v1/info`
- `GET /api/v1/tracks`
- `GET /api/v1/tracks?q=radio`

Run checks from this directory:

```bash
dart analyze
dart test
```
