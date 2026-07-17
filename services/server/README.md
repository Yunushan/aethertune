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
# Edit .env and replace the example operations token with a long random value.
docker compose up --build -d
docker compose ps
curl http://127.0.0.1:8080/health
```

`AETHERTUNE_SYNC_USERS` must remain valid JSON. Leave it as `{}` to use the
managed account registry described below. Static compatibility mode accepts a
single token, a token list, or named device tokens per account:

```text
{"primary":{"phone":"token-one","desktop":"token-two"}}
```

Any configured token can instead be `sha256:<64-hex-digest>`; the server
hashes the presented bearer token and compares it to that digest without
keeping the raw value in memory. Tokens must be unique across all account and
device entries; invalid or ambiguous values stop startup. Compose refuses
to start when the variable is absent, and `.env` is ignored by the image build
context. `AETHERTUNE_OPS_TOKEN` configures a separate bearer token for metrics
and managed account administration, accepts the same raw or `sha256:` form,
and is required by Docker Compose.

Compose binds to `127.0.0.1` by default. Use the supplied
[`deploy/Caddyfile`](deploy/Caddyfile) for HTTPS and see
[`deploy/README.md`](deploy/README.md) for Docker/Caddy, native systemd,
backup, update, and client-setup steps. Do not set a public bind address unless
the host firewall and a TLS proxy protect the service.

The native executable binds to `127.0.0.1` by default. Set
`AETHERTUNE_LISTEN_ADDRESS` only to an explicit IPv4 or IPv6 address when the
deployment needs another interface. Docker sets its own listener to `0.0.0.0`
inside the container; its published host port remains controlled separately by
`AETHERTUNE_BIND_ADDRESS`.

The in-process request limiter defaults to 120 requests per minute for each
bearer-token digest and one anonymous bucket. Set
`AETHERTUNE_RATE_LIMIT_PER_MINUTE` to a positive integer to tune that budget;
invalid values stop startup. Keep an additional rate limit at the reverse
proxy for IP-based protection.

Put the service behind a TLS-terminating reverse proxy before exposing it
outside a trusted LAN. Do not publish the container port directly to the
public internet, and do not commit populated `.env` files. The named
`aethertune-server-data` volume contains the latest per-account snapshots and
managed authentication registry; back it up before image or host maintenance.
Check the running image with
`docker compose ps` and update it with `docker compose up --build -d` after
reviewing release notes.

Available endpoints:

- `GET /health`
- `GET /api/v1/info`
- `GET /api/v1/metrics`
- `GET /api/v1/tracks`
- `GET /api/v1/tracks?q=radio`
- `GET /api/v1/auth/profile`
- `PATCH /api/v1/auth/profile`
- `GET /api/v1/admin/sync-accounts`
- `POST /api/v1/admin/sync-tokens`
- `DELETE /api/v1/admin/sync-tokens`
- `GET /api/v1/sync/library`
- `GET /api/v1/sync/library/metadata`
- `PUT /api/v1/sync/library`
- `DELETE /api/v1/sync/library`
- `GET /api/v1/listen-together/session`
- `PUT /api/v1/listen-together/session`
- `DELETE /api/v1/listen-together/session`
- `POST /api/v1/listen-together/session/invite`
- `GET /api/v1/listen-together/invites/{inviteCode}`
- `POST /api/v1/shared-playlists`
- `GET`/`PUT`/`DELETE /api/v1/shared-playlists/{playlistId}`
- `GET /api/v1/shared-playlists/{playlistId}/revisions`
- `POST`/`DELETE /api/v1/shared-playlists/{playlistId}/invites`
- `DELETE /api/v1/shared-playlists/{playlistId}/collaborators/{accountId}`
- `POST /api/v1/shared-playlist-invites/{inviteCode}`

The snapshot endpoints are disabled until either a static or managed device
token exists. Set `AETHERTUNE_DATA_DIR` to choose the durable snapshot and
authentication-registry directory. Requests require `Authorization: Bearer
<token>` and use optimistic `baseRevision` conflicts instead of automatic
merging. A successful `DELETE` records a revisioned tombstone rather than
erasing history, so stale devices cannot repopulate a cleared snapshot. The
service rejects local file paths and device cache jobs from portable snapshots.
`GET /api/v1/sync/library/metadata` returns only the authenticated account's
revision, timestamp, device label, and checksum. Current clients use it before
automatic uploads to avoid sending a stale full snapshot, then fall back to the
existing full-upload protocol when connecting to older servers without it.

The listen-together session endpoints are scoped to the same authenticated
account. They store a versioned, revision-protected queue of portable library
track IDs, current item, play state, and position only; they never store media
URLs, local paths, or provider credentials.

An active host can issue an opaque 144-bit invite code. A separately
authenticated guest can use that code to read the portable host session, but
cannot change it. The server stores only a SHA-256-derived invite filename and
does not return the host account identity to guests.

Private shared playlists are unlisted and have a distinct owner, editor, or
viewer role. They contain only a versioned playlist name and ordered portable
track IDs; stream URLs, local paths, credentials, artwork, and playback state
are rejected. Owners create opaque 144-bit viewer/editor invite codes, revoke
existing collaborators, and can delete the server playlist. Editors can update
against its current revision; viewers can only fetch it. Each invitation is
atomically consumed on a join, so it cannot be reused, and expires after seven
days if unused. Owners can invalidate every remaining unused code and issue
fresh replacements. Shared playlists and invite records are stored under
`AETHERTUNE_DATA_DIR`, using SHA-256-derived filenames for IDs/codes. Clients
must refresh explicitly after a revision conflict; there is no automatic merge
workflow. The mobile client provides an explicit non-destructive merge that
keeps the current server order and appends local-only track occurrences; the
editor chooses the local or server name. An editor can also restore an earlier
document through the regular revision-checked update endpoint, which records
it as a new revision. The server retains the latest 25 private playlist
revisions, and any authorized collaborator can inspect their checksum-verified
name, ordered track IDs, timestamp, and updating device.

## Managed accounts and device tokens

The operations API can create an account and issue a different token to each
device. It requires `AETHERTUNE_OPS_TOKEN` and fails closed when that token is
not configured. For example, issue the first phone token after startup:

```bash
curl --fail-with-body -X POST \
  -H "Authorization: Bearer $AETHERTUNE_OPS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"accountId":"primary","displayName":"Primary","deviceName":"Phone"}' \
  https://sync.example.com/api/v1/admin/sync-tokens
```

The response contains a 256-bit bearer token exactly once. Enter it in the
phone's AetherTune sync settings, then issue another token with the same
`accountId` and `deviceName` set to `Desktop`. Both devices authenticate as the
same snapshot owner without sharing a credential. The registry stores only
SHA-256 token digests under `AETHERTUNE_DATA_DIR/authentication`.

List account and non-secret device metadata with
`GET /api/v1/admin/sync-accounts`. Rotate a device token by repeating the
`POST` with `replaceTokenId` set to its listed token ID. The replacement is
committed atomically, and the old token stops authenticating immediately.
Each managed token also reports its last successful authentication time. The
server updates that operational field at most once per 24 hours per device, so
normal sync traffic does not create a registry write for every request. It
stores no bearer value, request path, address, or payload with the activity
timestamp.
Revoke without replacement using:

```bash
curl --fail-with-body -X DELETE \
  -H "Authorization: Bearer $AETHERTUNE_OPS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"accountId":"primary","tokenId":"listed-token-id"}' \
  https://sync.example.com/api/v1/admin/sync-tokens
```

An authenticated device can call `GET /api/v1/auth/profile` to verify its
account and device identity. Managed profile responses advertise
`"editable":true`; older servers and static credentials do not. A managed
device can atomically rename the shared account display name and its own device
label without changing its token, token ID, or creation time:

```bash
curl --fail-with-body -X PATCH \
  -H "Authorization: Bearer $AETHERTUNE_DEVICE_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"displayName":"Family library","deviceName":"Living room"}' \
  https://sync.example.com/api/v1/auth/profile
```

At least one field is required, labels are limited to 80 printable characters,
and a device label must remain unique within the account. Static credentials
return `409 profile_not_managed`. Public registration, password login, OAuth,
and automatic client-side token rotation are intentionally not exposed yet.

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
