#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "${1:-}" == '--session' ]]; then
  fixture="$2"
  evidence="$3"
  [[ "$HOME" == "$fixture" && "$AETHERTUNE_ACCEPTANCE_HOME" == "$fixture" ]]
  [[ "$(cat "$fixture/.aethertune-native-fixture")" == 'aethertune-native-acceptance-v1' ]]
  capture_pid=''
  keyring_pid=''
  cleanup_session() {
    status=$?
    if [[ -n "$capture_pid" ]]; then
      kill "$capture_pid" 2>/dev/null || true
      wait "$capture_pid" 2>/dev/null || true
    fi
    if [[ -n "$keyring_pid" ]]; then
      kill "$keyring_pid" 2>/dev/null || status=1
      wait "$keyring_pid" 2>/dev/null || true
    fi
    pulseaudio --kill 2>/dev/null || status=1
    exit "$status"
  }
  trap cleanup_session EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
  export PULSE_SINK=aethertune_acceptance
  pulseaudio -n --daemonize --exit-idle-time=-1 \
    --load='module-native-protocol-unix' \
    --load='module-null-sink sink_name=aethertune_acceptance rate=22050 channels=1' \
    --log-target="file:$evidence/pulseaudio.log"
  pactl set-default-sink aethertune_acceptance
  gnome-keyring-daemon --foreground --unlock --components=secrets \
    > "$evidence/keyring.log" 2>&1 <<< 'fixture-only-password' &
  keyring_pid=$!
  gdbus wait --session --timeout 10 org.freedesktop.secrets
  parec --device=aethertune_acceptance.monitor --format=s16le --rate=22050 \
    --channels=1 --raw > "$evidence/audio.raw" &
  capture_pid=$!
  cd "$ROOT/apps/mobile"
  for phase in seed migrate reopen sync; do
    target=integration_test/linux_native_acceptance_test.dart
    if [[ "$phase" == sync ]]; then
      target=integration_test/linux_sync_transport_acceptance_test.dart
    fi
    AETHERTUNE_ACCEPTANCE_PHASE="$phase" xvfb-run -a \
      -s '-screen 0 1280x900x24' flutter test \
      "$target" -d linux --no-pub \
      --reporter expanded 2>&1 | tee "$evidence/$phase.log"
    cp "$fixture/evidence/$phase.json" "$evidence/$phase.json"
    if [[ -f "$fixture/evidence/$phase.png" ]]; then
      cp "$fixture/evidence/$phase.png" "$evidence/$phase.png"
    fi
  done
  kill "$capture_pid"
  wait "$capture_pid" || true
  capture_pid=''
  python3 "$ROOT/scripts/ci/verify_native_audio.py" \
    --pcm "$evidence/audio.raw" --output "$evidence/audio.json"
  exit 0
fi

if [[ "${1:-}" != '--evidence' || $# != 2 ]]; then
  echo "Usage: $0 --evidence NEW_DIRECTORY" >&2
  exit 2
fi
[[ "$(uname -s)" == Linux ]]
for tool in flutter python3 openssl rustup dbus-run-session gnome-keyring-daemon pulseaudio pactl parec xvfb-run gdbus; do
  command -v "$tool" >/dev/null
done
evidence="$(realpath -m -- "$2")"
if [[ -e "$evidence" ]]; then
  echo "Evidence destination already exists: $evidence" >&2
  exit 2
fi
mkdir -p -- "$evidence"
fixture="$(mktemp -d /tmp/aethertune-native-acceptance.XXXXXXXX)"
printf '%s\n' 'aethertune-native-acceptance-v1' > "$fixture/.aethertune-native-fixture"
cleanup() {
  status=$?
  # Only this invocation's fresh, marked temporary home can be removed.
  if [[ "$fixture" == /tmp/aethertune-native-acceptance.* &&
        "$(realpath -- "$fixture")" == "$fixture" &&
        -f "$fixture/.aethertune-native-fixture" ]]; then
    rm -rf -- "$fixture"
  else
    echo 'Refused cleanup of an unexpected fixture path.' >&2
    exit 1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
mkdir -m 700 "$fixture/config" "$fixture/data" "$fixture/cache" "$fixture/runtime"
# Keep build toolchains separate from the disposable application profile.
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"

certificates="$fixture/certificates"
mkdir -m 700 "$certificates"
system_bundle="$(python3 -c 'import ssl; print(ssl.get_default_verify_paths().cafile or "")')"
if [[ ! -f "$system_bundle" ]]; then
  echo 'A readable platform CA bundle is required for native TLS acceptance.' >&2
  exit 1
fi
for name in trusted untrusted; do
  ca="$certificates/$name-ca"
  leaf="$certificates/$name-leaf"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$ca.key" -out "$ca.pem" \
    -days 2 -subj "/CN=AetherTune Synthetic $name CA" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' >> "$evidence/certificates.log" 2>&1
  openssl req -new -newkey rsa:2048 -nodes -keyout "$leaf.key" -out "$leaf.csr" \
    -subj '/CN=127.0.0.1' >> "$evidence/certificates.log" 2>&1
  openssl x509 -req -in "$leaf.csr" -CA "$ca.pem" -CAkey "$ca.key" -set_serial 1 \
    -out "$leaf.pem" -days 2 -extfile "$ROOT/scripts/ci/testdata/sync_transport_leaf.ext" \
    >> "$evidence/certificates.log" 2>&1
done
# The platform verifier reads this process-local bundle. No host/system trust
# store is modified, and neither the untrusted fixture CA nor private keys enter it.
cat "$system_bundle" "$certificates/trusted-ca.pem" > "$certificates/trusted-bundle.pem"
export SSL_CERT_FILE="$certificates/trusted-bundle.pem"
cp "$certificates/trusted-ca.pem" "$evidence/trusted-fixture-ca.pem"
export HOME="$fixture"
export AETHERTUNE_ACCEPTANCE_HOME="$fixture"
export XDG_CONFIG_HOME="$fixture/config"
export XDG_DATA_HOME="$fixture/data"
export XDG_CACHE_HOME="$fixture/cache"
export XDG_RUNTIME_DIR="$fixture/runtime"
export LIBGL_ALWAYS_SOFTWARE=1
export LANG=C
export LC_ALL=C
flutter --version --machine > "$evidence/flutter.json"
timeout --signal=TERM --kill-after=20s 18m \
  dbus-run-session -- bash "$0" --session "$fixture" "$evidence"
