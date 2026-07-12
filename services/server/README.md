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
