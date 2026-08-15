#!/usr/bin/env bash
set -euo pipefail

server_executable="${1:?Server executable path is required}"
evidence_directory="${2:-$(mktemp -d)}"
if [[ ! -x "$server_executable" ]]; then
  echo "Expected an executable server at $server_executable." >&2
  exit 1
fi

data_directory="$(mktemp -d)"
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
log_file="$data_directory/server.log"
server_pid=''

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$data_directory"
}
trap cleanup EXIT

mkdir -p "$evidence_directory"
env \
  AETHERTUNE_DATA_DIR="$data_directory/data" \
  AETHERTUNE_LISTEN_ADDRESS=127.0.0.1 \
  AETHERTUNE_OPS_TOKEN=ci-only-load-test-token \
  AETHERTUNE_SYNC_USERS='{}' \
  PORT="$port" \
  "$server_executable" >"$log_file" 2>&1 &
server_pid=$!

ready=false
for _ in $(seq 1 60); do
  if curl --fail --silent "http://127.0.0.1:$port/ready" >/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$log_file" >&2
    exit 1
  fi
  sleep 0.25
done

if [[ "$ready" != true ]]; then
  cat "$log_file" >&2
  echo 'Server did not become ready for the load smoke test.' >&2
  exit 1
fi

python3 scripts/ci/test_server_load.py \
  "http://127.0.0.1:$port" \
  "$evidence_directory/load-evidence.json"
