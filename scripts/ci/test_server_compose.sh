#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose=(docker compose --env-file .env.example)
test_port="${AETHERTUNE_TEST_PORT:-18080}"

cleanup() {
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$root/services/server"
export AETHERTUNE_PORT="$test_port"
export AETHERTUNE_BIND_ADDRESS=127.0.0.1
export AETHERTUNE_LISTEN_ADDRESS=0.0.0.0
export AETHERTUNE_SYNC_USERS='{}'
export AETHERTUNE_OPS_TOKEN='ci-only-compose-metrics-token'

"${compose[@]}" config --quiet
"${compose[@]}" up --build --detach

base_url="http://127.0.0.1:${AETHERTUNE_PORT}"
ready=0
for _ in $(seq 1 45); do
  if curl --fail --silent "$base_url/health" >/dev/null \
      && curl --fail --silent "$base_url/ready" >/dev/null; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" -ne 1 ]]; then
  "${compose[@]}" logs
  echo 'Docker Compose server did not become healthy and ready.' >&2
  exit 1
fi

curl --fail --silent "$base_url/api/v1/info" >/dev/null
unauthorized_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$base_url/api/v1/metrics")"
if [[ "$unauthorized_status" != '401' ]]; then
  echo "Docker metrics endpoint returned $unauthorized_status without authentication." >&2
  exit 1
fi
curl --fail --silent \
  -H "Authorization: Bearer $AETHERTUNE_OPS_TOKEN" \
  "$base_url/api/v1/metrics" >/dev/null
container_id="$("${compose[@]}" ps -q aethertune-server)"
if [[ -z "$container_id" ]]; then
  echo 'Docker Compose did not report a server container.' >&2
  exit 1
fi

if [[ "$(docker inspect --format '{{.Config.User}}' "$container_id")" != 'aethertune' ]]; then
  echo 'Docker server is not running as the unprivileged aethertune user.' >&2
  exit 1
fi
if [[ "$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$container_id")" != 'true' ]]; then
  echo 'Docker server root filesystem is not read-only.' >&2
  exit 1
fi
if ! docker inspect --format '{{json .HostConfig.CapDrop}}' "$container_id" | grep -q 'ALL'; then
  echo 'Docker server did not drop all Linux capabilities.' >&2
  exit 1
fi

echo 'Docker Compose server passed health, readiness, API, and container-hardening checks.'
