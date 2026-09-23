#!/usr/bin/env python3
"""Exercise authenticated sync against an owned, loopback-only compiled service."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import http.client
import json
import math
import os
from pathlib import Path
import secrets
import tempfile
import threading
import time

from server_recovery_runtime import ROOT, Server, require


ROUTE = '/api/v1/sync/library'
REQUEST_TIMEOUT = 5.0
MAX_RESPONSE_BYTES = 9 * 1024 * 1024
CYCLE_INTERVAL = 3.0


def encode(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(encode(value)).hexdigest()


def snapshot(account, cycle, device, tracks):
    return {
        'syncVersion': 1, 'version': 1,
        'name': f'{account}-cycle-{cycle}-device-{device}',
        'tracks': [
            {'id': f'{account}-track-{index}', 'title': f'Synthetic track {index}',
             'artist': 'Load fixture', 'durationMs': 180000}
            for index in range(tracks)
        ],
    }


class Client:
    def __init__(self, server):
        self.port = server.port
        self.measurements = []
        self.lock = threading.Lock()

    def request(self, method, route, token=None, body=None):
        started = time.monotonic()
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=REQUEST_TIMEOUT)
        status, received, failure = None, 0, None
        payload = None if body is None else encode(body)
        try:
            headers = {'content-type': 'application/json'}
            if token is not None:
                headers['authorization'] = 'Bearer ' + token
            connection.request(method, route, body=payload, headers=headers)
            stream_socket = connection.sock
            response = connection.getresponse()
            status = response.status
            chunks = []
            while not response.isclosed():
                remaining = REQUEST_TIMEOUT - (time.monotonic() - started)
                require(remaining > 0, 'Request exceeded the total time budget.')
                # read1 returns available bytes, allowing a total deadline even
                # if a response makes slow, intermittent progress.
                stream_socket.settimeout(remaining)
                chunk = response.read1(min(65536, MAX_RESPONSE_BYTES + 1 - received))
                if not chunk:
                    break
                received += len(chunk)
                require(received <= MAX_RESPONSE_BYTES, 'Response exceeded the byte budget.')
                chunks.append(chunk)
            require(response.length in (None, 0), 'Response ended before its declared content length.')
            decoded = json.loads(b''.join(chunks)) if received else None
            require(time.monotonic() - started <= REQUEST_TIMEOUT, 'Request exceeded the total time budget.')
            return status, decoded, dict(response.getheaders())
        except Exception as error:
            # Never retain tokens, request/response bodies, or arbitrary server errors.
            failure = type(error).__name__
            raise AssertionError(f'{method} {route}: {failure}') from None
        finally:
            connection.close()
            with self.lock:
                self.measurements.append({
                    'method': method, 'route': route, 'status': status,
                    'elapsed_ms': round((time.monotonic() - started) * 1000, 3),
                    'sent_bytes': len(payload or b''), 'received_bytes': received,
                    'failure': failure,
                })

    def expect(self, method, route, status=200, **kwargs):
        actual, body, _ = self.request(method, route, **kwargs)
        require(actual == status, f'{method} {route}: expected HTTP {status}, received {actual}.')
        return body


def verify_snapshot(client, token, expected, revision, device):
    response = client.expect('GET', ROUTE, token=token)
    require(response.get('revision') == revision, 'Committed revision was lost or changed.')
    require(response.get('snapshot') == expected, 'Snapshot content or account isolation failed.')
    require(response.get('checksum') == digest(expected), 'Snapshot checksum mismatch.')
    require(response.get('updatedByDevice') == device, 'Winning device metadata mismatch.')
    metadata = client.expect('GET', ROUTE + '/metadata', token=token)
    require(metadata.get('revision') == revision and metadata.get('checksum') == digest(expected),
            'Metadata disagrees with the committed snapshot.')
    require('snapshot' not in metadata, 'Metadata endpoint leaked the snapshot body.')


def account_cycle(client, account, tokens, revision, cycle, tracks):
    gate = threading.Barrier(2)
    candidates = [snapshot(account, cycle, index, tracks) for index in range(2)]
    devices = [f'{account}-device-{index}' for index in range(2)]

    def write(index):
        gate.wait(timeout=REQUEST_TIMEOUT)
        return client.request('PUT', ROUTE, token=tokens[index], body={
            'baseRevision': revision, 'deviceId': devices[index], 'snapshot': candidates[index],
        })

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(write, range(2)))
    require(sorted(result[0] for result in results) == [200, 409],
            'Concurrent same-revision writes must have exactly one winner and one conflict.')
    winner = next(index for index, result in enumerate(results) if result[0] == 200)
    saved, conflict = results[winner][1], results[1 - winner][1]
    expected = candidates[winner]
    require(saved.get('revision') == revision + 1 and saved.get('checksum') == digest(expected),
            'Write acknowledgment does not identify the winning snapshot.')
    require(conflict.get('error') == 'sync_conflict' and conflict.get('currentRevision') == revision + 1,
            'Conflict did not report the current committed revision.')
    require(conflict.get('checksum') == digest(expected), 'Conflict checksum does not identify the winner.')
    verify_snapshot(client, tokens[1 - winner], expected, revision + 1, devices[winner])
    return {'snapshot': expected, 'revision': revision + 1, 'device': devices[winner]}


def verify_rate_limit(client, token, same_account_token, unaffected_token):
    rejected = False
    for _ in range(121):
        status, body, headers = client.request('GET', ROUTE + '/metadata', token=token)
        if status == 429:
            require(body.get('error') == 'rate_limited', 'Wrong rate-limit response.')
            retry = next((value for key, value in headers.items() if key.lower() == 'retry-after'), '')
            require(retry.isdigit() and 1 <= int(retry) <= 60, 'Missing or invalid rate-limit retry guidance.')
            rejected = True
            break
        require(status == 200, 'Unexpected response before the account rate limit.')
    require(rejected, 'Default account rate limit was not enforced.')
    client.expect('GET', ROUTE + '/metadata', status=429, token=same_account_token)
    client.expect('GET', ROUTE, token=unaffected_token)
    client.expect('GET', '/health')


def summarize(measurements):
    durations = sorted(item['elapsed_ms'] for item in measurements)
    return {
        'requests': len(measurements),
        'p50_ms': durations[math.ceil(len(durations) * .50) - 1] if durations else None,
        'p95_ms': durations[math.ceil(len(durations) * .95) - 1] if durations else None,
        'max_ms': max(durations, default=None),
        'sent_bytes': sum(item['sent_bytes'] for item in measurements),
        'received_bytes': sum(item['received_bytes'] for item in measurements),
        'transport_failures': sum(item['failure'] is not None for item in measurements),
        'status_counts': {str(status): sum(item['status'] == status for item in measurements)
                          for status in sorted({item['status'] for item in measurements}, key=str)},
    }


def input_hashes():
    files = [Path(__file__), ROOT / 'scripts/ci/server_recovery_runtime.py',
             ROOT / 'services/server/pubspec.yaml', ROOT / 'services/server/pubspec.lock']
    for directory in ('bin', 'lib'):
        files.extend((ROOT / 'services/server' / directory).rglob('*.dart'))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(files)}


def run(executable, evidence, *, seconds=65, accounts=4, tracks=1000):
    require(5 <= seconds <= 600, 'Duration must be between 5 and 600 seconds.')
    require(2 <= accounts <= 8, 'Account count must be between 2 and 8.')
    require(1 <= tracks <= 10000, 'Tracks per snapshot must be between 1 and 10000.')
    executable = executable.resolve(strict=True)
    evidence.mkdir(parents=True, exist_ok=False)
    report = {
        'schema_version': 1, 'result': 'failed',
        'timestamp_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': os.environ.get('SOURCE_COMMIT_SHA'),
        'input_sha256': input_hashes(),
        'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
        'scope': 'owned-loopback-http-compiled-server; not deployed TLS or production capacity',
        'configuration': {'seconds': seconds, 'accounts': accounts, 'devices_per_account': 2,
                          'tracks_per_snapshot': tracks, 'cycle_interval_seconds': CYCLE_INTERVAL,
                          'request_timeout_seconds': REQUEST_TIMEOUT, 'rate_limits': 'production defaults'},
        'checks': [],
    }
    clients = []
    started = time.monotonic()
    try:
        with tempfile.TemporaryDirectory(prefix='aethertune-auth-load-') as temporary:
            root = Path(temporary)
            operations = secrets.token_urlsafe(32)
            credentials, states = {}, {}
            with Server(executable, root / 'data', root / 'server.log', operations) as server:
                client = Client(server)
                clients.append(client)
                for index in range(accounts):
                    account = f'load-account-{index}'
                    credentials[account] = [
                        client.expect('POST', '/api/v1/admin/sync-tokens', status=201,
                                      token=operations, body={'accountId': account, 'deviceName': f'load-device-{device}'})['token']
                        for device in range(2)
                    ]
                    empty = client.expect('GET', ROUTE, token=credentials[account][0])
                    require(empty.get('revision') == 0 and empty.get('snapshot') is None,
                            'A disposable account already contains a snapshot.')
                client.expect('GET', ROUTE, status=401)
                client.expect('GET', ROUTE, status=401, token=secrets.token_urlsafe(32))
                report['checks'].append('managed-account-setup-and-unauthorized-rejection')
                cycle, load_started = 0, time.monotonic()
                offset = len(client.measurements)
                with ThreadPoolExecutor(max_workers=accounts) as pool:
                    while time.monotonic() - load_started < seconds:
                        cycle_started = time.monotonic()
                        pending = {account: pool.submit(account_cycle, client, account, tokens,
                                   states.get(account, {}).get('revision', 0), cycle, tracks)
                                   for account, tokens in credentials.items()}
                        states = {account: future.result() for account, future in pending.items()}
                        cycle += 1
                        time.sleep(max(0, min(CYCLE_INTERVAL - (time.monotonic() - cycle_started),
                                             seconds - (time.monotonic() - load_started))))
                require(cycle >= 2, 'Too few completed cycles to establish repeated sync behavior.')
                report['workload'] = {
                    **summarize(client.measurements[offset:]), 'cycles_per_account': cycle,
                    'elapsed_seconds': round(time.monotonic() - load_started, 3),
                    'successful_writes': accounts * cycle, 'expected_conflicts': accounts * cycle,
                }
                report['checks'].extend(['concurrent-device-conflicts', 'cross-account-content-isolation',
                                         'readback-and-metadata-checksums'])
            # The existing owned Server fixture kills and waits for its process.
            # Reopen unchanged data with the same credentials, not a fresh registry.
            with Server(executable, root / 'data', root / 'server.log', operations) as restarted:
                client = Client(restarted)
                clients.append(client)
                for account, state in states.items():
                    for token in credentials[account]:
                        verify_snapshot(client, token, state['snapshot'], state['revision'], state['device'])
                report['checks'].append('acknowledged-snapshots-and-device-credentials-survive-process-kill')
                tokens = list(credentials.values())
                verify_rate_limit(client, tokens[0][0], tokens[0][1], tokens[1][0])
                report['checks'].append('default-account-rate-limit-and-unaffected-account-availability')
        report['result'] = 'passed'
    except Exception as error:
        report['error_type'] = type(error).__name__
        # Only our assertion messages are safe to publish; server bodies and
        # credentials never enter those messages.
        if isinstance(error, AssertionError):
            report['error'] = str(error)
    finally:
        report['elapsed_seconds'] = round(time.monotonic() - started, 3)
        report['all_requests'] = summarize([item for client in clients for item in client.measurements])
        (evidence / 'authenticated-sync-load.json').write_text(
            json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        print(json.dumps(report, sort_keys=True))
    return 0 if report['result'] == 'passed' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=65)
    parser.add_argument('--accounts', type=int, default=4)
    parser.add_argument('--tracks', type=int, default=1000)
    args = parser.parse_args()
    return run(args.executable, args.evidence, seconds=args.seconds, accounts=args.accounts, tracks=args.tracks)


if __name__ == '__main__':
    raise SystemExit(main())
