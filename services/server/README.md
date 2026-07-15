# AetherTune Server

This is the Dart HTTP service for AetherTune server-side features.

```bash
dart pub get
dart run bin/server.dart
```

## Docker deployment

The checked-in Docker image compiles a self-contained server executable and
runs it as an unprivileged user. It uses a named Docker volume for durable
snapshots and a `/health` health check.

```bash
cd services/server
cp .env.example .env
# Edit .env and replace the example bearer token with a long random value.
docker compose up --build -d
docker compose ps
curl http://127.0.0.1:8080/health
```

`AETHERTUNE_SYNC_USERS` must remain valid JSON, for example
`{"phone":"token-one","desktop":"token-two"}`. The account ID is the
server-side sync user; each client enters its corresponding bearer token in
the app. For deployments with a managed secret store, a value can instead be
`sha256:<64-hex-digest>`; the server hashes the client bearer token and compares
it to that digest without keeping the raw value in memory. Invalid digest
values stop startup with a configuration error. Compose refuses to start when
the variable is absent, and `.env` is ignored by the image build context.
`AETHERTUNE_OPS_TOKEN` configures a separate bearer token for operational
metrics and accepts the same raw or `sha256:` form. Docker Compose requires it.

Compose binds to `127.0.0.1` by default. Use the supplied
[`deploy/Caddyfile`](deploy/Caddyfile) for HTTPS and see
[`deploy/README.md`](deploy/README.md) for Docker/Caddy, native systemd,
backup, update, and client-setup steps. Do not set a public bind address unless
the host firewall and a TLS proxy protect the service.

Put the service behind a TLS-terminating reverse proxy before exposing it
outside a trusted LAN. Do not publish the container port directly to the
public internet, and do not commit populated `.env` files. The named
`aethertune-server-data` volume contains the latest per-user snapshots; back
it up before image or host maintenance. Check the running image with
`docker compose ps` and update it with `docker compose up --build -d` after
reviewing release notes.

Available endpoints:

- `GET /health`
- `GET /api/v1/info`
- `GET /api/v1/metrics`
- `GET /api/v1/tracks`
- `GET /api/v1/tracks?q=radio`
- `GET /api/v1/sync/library`
- `PUT /api/v1/sync/library`
- `DELETE /api/v1/sync/library`

The snapshot endpoints are disabled unless `AETHERTUNE_SYNC_USERS` contains a
JSON object mapping user IDs to bearer tokens. Set `AETHERTUNE_DATA_DIR` to
choose the durable snapshot directory. Requests require `Authorization: Bearer
<token>` and use optimistic `baseRevision` conflicts instead of automatic
merging. A successful `DELETE` records a revisioned tombstone rather than
erasing history, so stale devices cannot repopulate a cleared snapshot. The
service rejects local file paths and device cache jobs from portable snapshots.

`GET /api/v1/metrics` reports only process-lifetime aggregate state: start
time, uptime, total request count, and whether library sync is configured. It
does not record or expose users, bearer tokens, request paths, addresses, or
payloads. The count includes the metrics request itself and resets when the
server restarts. When `AETHERTUNE_OPS_TOKEN` is set, requests require
`Authorization: Bearer <operations-token>` and rejected tokens are never
echoed. Keep the endpoint behind the same private network or proxy access
policy as the rest of the service.

The server executable writes one JSON log line for each handled request with
only a timestamp, HTTP method, normalized known route (or `/not-found`), status
code, and duration. Query strings, request bodies, headers, addresses, user
IDs, and tokens are never included. A log-sink failure cannot affect the
request response.

Run checks from this directory:

```bash
dart analyze
dart test
```
