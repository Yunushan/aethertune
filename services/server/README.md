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
- `GET /api/v1/sync/library`
- `PUT /api/v1/sync/library`

The snapshot endpoints are disabled unless `AETHERTUNE_SYNC_USERS` contains a
JSON object mapping user IDs to bearer tokens. Set `AETHERTUNE_DATA_DIR` to
choose the durable snapshot directory. Requests require `Authorization: Bearer
<token>` and use optimistic `baseRevision` conflicts instead of automatic
merging. The service rejects local file paths and device cache jobs from
portable snapshots.

Run checks from this directory:

```bash
dart analyze
dart test
```
