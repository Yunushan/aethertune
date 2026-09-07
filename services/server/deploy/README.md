# Production Deployment

The AetherTune client requires HTTPS by default. Keep the server on loopback
and use a TLS reverse proxy for public access. The sync service stores only
portable library snapshots. Back up its state before host or image changes.

## Docker and Caddy

1. Copy `services/server/.env.example` to `services/server/.env`, leave
   `AETHERTUNE_SYNC_USERS={}` for managed accounts, and set a long random
   `AETHERTUNE_OPS_TOKEN`. Keep `AETHERTUNE_BIND_ADDRESS=127.0.0.1`; Docker
   uses `AETHERTUNE_LISTEN_ADDRESS=0.0.0.0` only inside its network namespace.
   Startup rejects the checked-in placeholder value, so replace it before
   running Compose.
2. Start the service with `docker compose up --build -d` from
   `services/server`.
3. Issue a separate managed token for each phone or desktop through
   `POST /api/v1/admin/sync-tokens`, using the same `accountId` for devices
   that should share a snapshot. The complete commands and rotation/revocation
   flow are in `services/server/README.md`.
4. Copy `deploy/Caddyfile` to the Caddy configuration directory, replace
   `sync.example.com`, then validate and reload Caddy:

   ```bash
   caddy validate --config /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

5. Verify both paths:

   ```bash
   curl --fail http://127.0.0.1:8080/health
   curl --fail http://127.0.0.1:8080/ready
   curl --fail https://sync.example.com/health
   curl --fail https://sync.example.com/ready
   curl --fail -H 'Authorization: Bearer your-operations-token' \
     https://sync.example.com/api/v1/metrics
   ```

The container has no shell, curl, or package manager. For an internal readiness
check, run `docker compose exec -T aethertune-server /usr/local/bin/aethertune-healthcheck`;
use the host's curl and `docker compose logs` for further diagnostics. The probe
checks the unauthenticated loopback readiness contract with a bounded deadline.

The runtime retains UID/GID `10001:999` from the previous image, so existing
named-volume data does not need an ownership migration. New data directories use
mode `0700`. Back up the volume before an update, preserve its existing ownership,
and verify saved snapshots and token revocation after replacement. Bind-mounted
data must also be accessible to this numeric identity; do not fix permissions
by making private state world-writable. Local old-image/new-image acceptance is
not proof of rollback between different application or schema versions.

The supplied Caddy configuration adds HSTS, content-type sniffing, framing,
and referrer protections. Feed the protected `/api/v1/metrics` response into
the host's monitoring system and alert on a failed `/ready` probe, any 5xx
responses, a sustained increase in `requestsRateLimited`, or a stopped
`aethertune.service`/container. Keep alerting outside the server process so a
host or process failure remains observable.

Do not change `AETHERTUNE_BIND_ADDRESS` to a public interface when using this
reverse proxy. Caddy is the only process that should accept internet traffic.

## Native systemd Service

Build a release executable on the target architecture, then install it and the
unit file:

```bash
cd services/server
dart pub get --enforce-lockfile
dart compile exe bin/server.dart -o aethertune-server
sudo install -m 0755 aethertune-server /usr/local/bin/aethertune-server
sudo install -m 0644 deploy/aethertune.service /etc/systemd/system/aethertune.service
sudo install -d -m 0700 /etc/aethertune
sudo install -m 0600 deploy/server.env.example /etc/aethertune/server.env
sudo systemctl daemon-reload
sudo systemctl enable --now aethertune
sudo systemctl status aethertune
```

The native service listens on `PORT` (default `8080`; configured values must be
from `1` through `65535`) and
`AETHERTUNE_LISTEN_ADDRESS` (default `127.0.0.1`), then writes snapshots to the
systemd-managed `/var/lib/aethertune` state directory. Place the supplied
`Caddyfile` in front of the service exactly as in the Docker setup.

Install the checked-in backup service and timer after creating the backup
directory. The timer creates a checksum-verified archive every day and keeps
30 days by default. Install Python 3.10 or newer on the backup/restore host and
keep the Python helper beside all three shell entry points:

```bash
sudo install -m 0755 deploy/aethertune-backup.sh /usr/local/libexec/aethertune-backup.sh
sudo install -m 0644 deploy/aethertune-backup.py /usr/local/libexec/aethertune-backup.py
sudo install -m 0755 deploy/aethertune-restore.sh /usr/local/libexec/aethertune-restore.sh
sudo install -m 0755 deploy/aethertune-verify-backups.sh /usr/local/libexec/aethertune-verify-backups.sh
sudo install -m 0755 deploy/aethertune-rollback.sh /usr/local/libexec/aethertune-rollback.sh
sudo install -m 0755 deploy/aethertune-ops-probe.sh /usr/local/libexec/aethertune-ops-probe.sh
sudo install -m 0644 deploy/aethertune-backup.service /etc/systemd/system/aethertune-backup.service
sudo install -m 0644 deploy/aethertune-backup.timer /etc/systemd/system/aethertune-backup.timer
sudo install -m 0644 deploy/aethertune-backup-verify.service /etc/systemd/system/aethertune-backup-verify.service
sudo install -m 0644 deploy/aethertune-backup-verify.timer /etc/systemd/system/aethertune-backup-verify.timer
sudo install -m 0644 deploy/aethertune-ops-probe.service /etc/systemd/system/aethertune-ops-probe.service
sudo install -m 0644 deploy/aethertune-ops-probe.timer /etc/systemd/system/aethertune-ops-probe.timer
sudo install -d -m 0700 /var/backups/aethertune
sudo systemctl daemon-reload
sudo systemctl enable --now aethertune-backup.timer
sudo systemctl enable --now aethertune-backup-verify.timer
sudo systemctl enable --now aethertune-ops-probe.timer
systemctl list-timers aethertune-backup.timer aethertune-backup-verify.timer aethertune-ops-probe.timer
```

Before a restore, stop `aethertune.service`, move the existing data directory
aside, and run `aethertune-restore.sh` with the archive and an empty target.
The restore refuses missing or mismatched checksums, unsafe/aliased archive
paths, links and special files, runtime locks, inconsistent manifests, and
non-empty targets. It writes into a private sibling staging directory, verifies
file hashes, flushes files, and publishes the directory only after validation.
Ensure the restored directory is owned by the service's configured identity
before restart; the helper never guesses or changes that identity.

New backups take a coordinated snapshot across the library, authentication,
provider, playlist, and invitation stores. The helper first prevents new data
requests, then waits for admitted requests to finish. During this interval data
requests return HTTP 503 with Retry-After, while `/health` stays available.
`/ready` is unavailable during the snapshot; monitors should distinguish a
bounded backup window from an unexpected outage. Backups briefly reduce
availability, so schedule them during a quiet period and measure their duration.

First-byte record locks are shared between the Python helper and Dart server.
Run both against the same local filesystem; network filesystems with different
lock semantics are not validated. Lock acquisition defaults to 30 seconds per
lock and a timeout publishes no archive. An old executable holding the legacy
exclusive `.server.lock` is deliberately incompatible: stop it before taking a
backup, or upgrade it to the coordinated implementation. Do not mix the old
uncoordinated shell helper with a running new server. The systemd backup unit
needs write access to `/var/lib/aethertune` only to open the coordination locks;
the helper does not modify application data.

New POSIX lock files created by a root-run helper inherit the data directory's
numeric owner/group and mode `0600`. This allows a non-root server to open them
after an offline backup or legacy upgrade. Existing lock inodes, ownership, and
permissions are preserved; they are never replaced to obtain a lock. Symlink,
hard-linked, and special lock files are rejected. If a previous helper left
incorrect ownership, stop the server and all backup/verification jobs before
correcting only the verified lock paths for the configured service identity.
Never delete or replace a lock file while any process may still hold it.

Archives have unique names, a SHA-256 sidecar, and a per-file manifest. The
default uncompressed data limit is 16 GiB, with 100,000 files and bounded
metadata. Adjust `--max-bytes` deliberately for a larger deployment. These are
logical bounds, not physical disk reservations. Legacy checksum-only archives
can be restored after validation but report `manifestVerified: false`.
Checksums detect corruption, not malicious replacement of both archive and
sidecar. Protect backups with host permissions and authenticated off-host
storage; they contain private user state and authentication digests.

The separate verification timer checks every retained archive's checksum
sidecar, member types/paths, and file manifest each day after the backup timer. This detects later
archive corruption; copy verified archives to storage outside the host if
host-loss recovery is required.

## Tokens, Backups, and Updates

Generate the operations bearer token outside shell history. For a hash-only
server configuration, hash it before placing it in
`/etc/aethertune/server.env`:

```bash
printf '%s' 'replace-with-a-secret-token' | sha256sum | awk '{print "sha256:" $1}'
```

Managed device tokens are generated by the server, returned once, and stored
only as SHA-256 digests. Static `AETHERTUNE_SYNC_USERS` tokens remain available
for compatibility and support nested device-token objects. For Docker, stop the
service before archiving its named volume, or run the matching Python helper on
the same host with access to that volume and verified local lock semantics.
Do not archive a live volume with an uncoordinated `tar` command. For systemd, run the installed backup
service for a one-off verified archive; both backups include the managed
authentication registry:

```bash
sudo systemctl start aethertune-backup.service
sudo systemctl start aethertune-backup-verify.service
```

PR CI, the scheduled recovery drill, and release executable jobs also run a
real compiled-service drill. It exercises a backup during an incomplete upload,
exact restored snapshots, provider settings, managed identities, revoked
tokens, account isolation, revision conflicts, one-time recovery codes,
kill/restart persistence, and lock release after terminating a backup owner:

```bash
python3 ../../scripts/ci/server_recovery_runtime.py \
  --executable build/aethertune-server \
  --evidence ../../build/server-runtime-recovery
```

Linux CI, the scheduled drill, and Linux server releases also execute the real
systemd unit restrictions using uniquely named disposable fixtures. On a Linux
test host with systemd and root access, run from the repository root:

```bash
sudo -n python3 scripts/ci/test_server_backup_privileges.py
sudo -n python3 scripts/ci/server_systemd_runtime.py \
  --executable services/server/build/aethertune-server \
  --evidence build/server-systemd-recovery
```

This starts isolated copies of the checked-in server and backup units, retaining
`DynamicUser`, private devices, restricted address families, and the strict
filesystem sandbox. It changes only fixture paths, the loopback port, and test
credentials; it does not install or modify `aethertune.service`. It verifies a
root backup of non-root state, restore ownership, exact snapshots, revoked
credentials, post-restore writes, and restart persistence. Temporary units and
their state are stopped and removed; cleanup errors fail the test and identify
the fixture that needs inspection. Unit journals are checked for test credential
leaks before redacted evidence is retained. Use a disposable CI/test host, not a
production server, for this privileged validation.

For a real restore, preserve the original data directory until validation is
complete. Before moving it, record its actual resolved path and numeric owner
and group; `DynamicUser` state may reside under `/var/lib/private/`. After the
restore helper validates and publishes an empty replacement target, restore
that recorded ownership to the directory and its regular files before starting
the service. Do not guess a dynamic UID or recursively change unrelated paths.
The fixture exercises this sequence; it does not establish power-loss behavior,
different-version rollback, off-host recovery, or production RPO/RTO.

The resulting JSON records executable SHA-256 and controlled timing. This
fixture does not establish production RPO/RTO, power-loss durability, systemd
restore ownership, or rollback compatibility between different release schemas.

Run the same health, readiness, and authenticated metrics contract used by
Compose against the deployed endpoint. The scheduled systemd probe checks the
loopback service every five minutes and exits non-zero when any endpoint or
metrics counter is unhealthy; collect its journal/failure state in the host's
monitoring system. Set `AETHERTUNE_OPS_PROBE_TOKEN` in the root-only env file
to the raw operations token. This is required when the server's
`AETHERTUNE_OPS_TOKEN` is stored as a `sha256:` digest; never put the probe
token in a unit file or command-line argument. The probe accepts HTTPS for
remote hosts and loopback HTTP for local checks only:

```bash
AETHERTUNE_OPS_PROBE_TOKEN='your-operations-token' \
  /usr/local/libexec/aethertune-ops-probe.sh https://sync.example.com
```

For a remote monitor, run the same probe against the public HTTPS URL from a
separate host or monitoring worker. Local systemd timers cannot detect a
complete host outage, so retain an off-host alert for public `/ready` failures,
5xx responses, rate-limit spikes, and missing probe/backup timer runs.

Test updates on a backup first. After an update, verify `/health` locally and
through HTTPS before configuring the AetherTune app in Options with the public
`https://` URL, a device name, and its matching bearer token.

Keep the previous server executable beside the live one before an update so an
atomic rollback is available:

```bash
sudo install -m 0755 /usr/local/bin/aethertune-server /usr/local/libexec/aethertune-server.previous
sudo systemctl restart aethertune.service
curl --fail http://127.0.0.1:8080/ready
```

If the updated binary fails readiness, restore the previous executable and
restart the service:

```bash
sudo /usr/local/libexec/aethertune-rollback.sh \
  /usr/local/bin/aethertune-server \
  /usr/local/libexec/aethertune-server.previous
sudo systemctl restart aethertune.service
curl --fail http://127.0.0.1:8080/ready
```

The rollback helper installs beside the live binary and renames it into place
on the same filesystem, avoiding a partially written executable. Record the
release, readiness result, rollback decision, and final checksum in the
deployment log.
