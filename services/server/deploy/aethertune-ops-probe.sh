#!/usr/bin/env bash
set -euo pipefail

base_url="${1:?Usage: aethertune-ops-probe.sh BASE_URL}"
ops_token="${AETHERTUNE_OPS_PROBE_TOKEN:-${AETHERTUNE_OPS_TOKEN:-}}"
if [[ -z "$ops_token" ]]; then
  echo 'AETHERTUNE_OPS_PROBE_TOKEN or AETHERTUNE_OPS_TOKEN is required' >&2
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
curl_options=(--fail --silent --show-error --connect-timeout 5 --max-time 15)
curl "${curl_options[@]}" "$base_url/health" >/dev/null
curl "${curl_options[@]}" "$base_url/ready" >/dev/null
metrics_body="$(curl "${curl_options[@]}" \
  -H "Authorization: Bearer $ops_token" \
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
