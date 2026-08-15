#!/usr/bin/env python3
"""Run a bounded, credential-free HTTP load smoke test against a local server."""

from __future__ import annotations

import concurrent.futures
import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


REQUESTS_PER_ROUTE = 20
MAX_WORKERS = 8
MAX_REQUEST_SECONDS = 2.0
ROUTES = ("/health", "/ready", "/api/v1/info", "/api/v1/tracks")


def _request(base_url: str, route: str, sequence: int) -> dict[str, object]:
    started = time.perf_counter()
    request = Request(
        f"{base_url.rstrip('/')}{route}",
        headers={"Authorization": f"Bearer load-probe-{sequence}"},
    )
    try:
        with urlopen(request, timeout=MAX_REQUEST_SECONDS) as response:
            status = response.status
            response.read()
        error = None if status == 200 else f"unexpected HTTP status {status}"
    except HTTPError as exc:
        status = exc.code
        error = f"unexpected HTTP status {exc.code}"
    except (TimeoutError, URLError, OSError) as exc:
        status = None
        error = str(exc)
    duration_ms = (time.perf_counter() - started) * 1000
    if duration_ms > MAX_REQUEST_SECONDS * 1000:
        error = error or f"request exceeded {MAX_REQUEST_SECONDS:.1f}s"
    return {
        "route": route,
        "sequence": sequence,
        "status": status,
        "duration_ms": round(duration_ms, 3),
        "error": error,
    }


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    index = max(0, math.ceil(len(values) * percentile) - 1)
    return round(sorted(values)[index], 3)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: test_server_load.py BASE_URL EVIDENCE_JSON")
    base_url, evidence_path_value = sys.argv[1:]
    evidence_path = Path(evidence_path_value)
    evidence_path.parent.mkdir(parents=True, exist_ok=True)

    work = [
        (route, sequence)
        for sequence, route in enumerate(
            route for route in ROUTES for _ in range(REQUESTS_PER_ROUTE)
        )
    ]
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        results = list(
            pool.map(
                lambda item: _request(base_url, item[0], item[1]),
                work,
            )
        )
    elapsed_ms = (time.perf_counter() - started) * 1000
    durations = [float(result["duration_ms"]) for result in results]
    failures = [result for result in results if result["error"] is not None]
    evidence = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "base_url_host": base_url.split("//", 1)[-1].split("/", 1)[0],
        "routes": list(ROUTES),
        "requests": len(results),
        "workers": MAX_WORKERS,
        "requests_per_route": REQUESTS_PER_ROUTE,
        "elapsed_ms": round(elapsed_ms, 3),
        "p50_ms": _percentile(durations, 0.50),
        "p95_ms": _percentile(durations, 0.95),
        "max_ms": round(max(durations, default=0.0), 3),
        "status_counts": {
            str(status): sum(result["status"] == status for result in results)
            for status in sorted({result["status"] for result in results}, key=str)
        },
        "failures": failures,
        "result": "passed" if not failures else "failed",
    }
    evidence_path.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(evidence, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
