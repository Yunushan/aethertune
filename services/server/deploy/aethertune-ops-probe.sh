#!/usr/bin/env bash
set -euo pipefail

base_url="${1:?Usage: aethertune-ops-probe.sh BASE_URL}"
metrics_token="${AETHERTUNE_OPS_PROBE_TOKEN:-${AETHERTUNE_METRICS_TOKEN:-}}"
if [[ -z "$metrics_token" ]]; then
  echo 'AETHERTUNE_OPS_PROBE_TOKEN or AETHERTUNE_METRICS_TOKEN is required' >&2
  exit 2
fi

case "$base_url" in
  https://*|http://127.0.0.1:*|http://localhost:*) ;;
  *)
    echo 'BASE_URL must use HTTPS, or loopback HTTP for a local probe.' >&2
    exit 2
    ;;
esac

base_url="${base_url%/}"
case "$base_url" in
  *'?'*|*'#'*|*'@'*)
    echo 'BASE_URL must not contain credentials, query parameters, or fragments.' >&2
    exit 2
    ;;
esac
curl_options=(--fail --silent --show-error --connect-timeout 5 --max-time 15)
validate_status_response() {
  local endpoint="$1"
  local expected_status="$2"
  local body="$3"
  python3 -c '
import json
import sys

endpoint, expected_status = sys.argv[1:]
try:
    payload = json.load(sys.stdin)
except ValueError:
    raise SystemExit(f"{endpoint} response is not valid JSON")
if not isinstance(payload, dict) or payload.get("service") != "aethertune-server" or payload.get("status") != expected_status:
    raise SystemExit(f"{endpoint} response failed the server status contract")
' "$endpoint" "$expected_status" <<< "$body"
}

health_body="$(curl "${curl_options[@]}" "$base_url/health")"
validate_status_response /health ok "$health_body"
ready_body="$(curl "${curl_options[@]}" "$base_url/ready")"
validate_status_response /ready ready "$ready_body"
metrics_body="$(curl "${curl_options[@]}" \
  -H "Authorization: Bearer $metrics_token" \
  "$base_url/api/v1/metrics")"

python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("service") != "aethertune-server":
    raise SystemExit("metrics response identified an unexpected service")
for name in ("requestsTotal", "requestsRateLimited", "responses5xx"):
    value = payload.get(name)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise SystemExit(f"metrics response contains an invalid {name} counter")
requests_total = payload["requestsTotal"]
requests_rate_limited = payload["requestsRateLimited"]
responses_5xx = payload["responses5xx"]
print(
    "AetherTune operational probe passed: "
    f"requestsTotal={requests_total} "
    f"requestsRateLimited={requests_rate_limited} "
    f"responses5xx={responses_5xx}"
)
' <<< "$metrics_body"
