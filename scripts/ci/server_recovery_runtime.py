#!/usr/bin/env python3
"""Recover a real compiled service and exercise its cross-process backup fence."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import platform
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'services/server/deploy/aethertune-backup.py'
SPEC = importlib.util.spec_from_file_location('server_backup', HELPER)
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)
PROCESS_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def require_default_token_expiry(device):
    require('expiresAt' in device, 'Managed token has no expiration metadata.')
    created = datetime.fromisoformat(device['createdAt'])
    expires = datetime.fromisoformat(device['expiresAt'])
    require(expires - created == timedelta(days=365), 'Managed token does not have the default lifetime.')


class Server:
    def __init__(self, executable, data, log, operations):
        self.executable, self.data, self.log, self.operations = executable, data, log, operations
        self.process = None

    def __enter__(self):
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            self.port = reservation.getsockname()[1]
        environment = {key: value for key, value in os.environ.items() if not key.startswith('AETHERTUNE_')}
        environment.update(AETHERTUNE_DATA_DIR=str(self.data), AETHERTUNE_OPS_TOKEN=self.operations,
                           AETHERTUNE_SYNC_USERS='{}', AETHERTUNE_LISTEN_ADDRESS='127.0.0.1', PORT=str(self.port))
        self.output = self.log.open('ab')
        self.process = subprocess.Popen([str(self.executable)], env=environment, stdout=self.output,
                                        stderr=subprocess.STDOUT, creationflags=PROCESS_FLAGS)
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                require(self.process.poll() is None, 'Server exited before becoming healthy; inspect runtime log.')
                try:
                    if self.request('GET', '/health')[0] == 200:
                        return self
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.05)
            raise AssertionError('Server startup timed out.')
        except BaseException:
            self.__exit__()
            raise

    def __exit__(self, *unused):
        if self.process is not None and self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=10)
        self.output.close()

    def request(self, method, path, token=None, body=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        try:
            headers = {'content-type': 'application/json'}
            if token is not None:
                headers['authorization'] = 'Bearer ' + token
            connection.request(method, path, body=None if body is None else json.dumps(body), headers=headers)
            response = connection.getresponse()
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
        finally:
            connection.close()

    def expect(self, method, path, status=200, **kwargs):
        actual, body = self.request(method, path, **kwargs)
        require(actual == status, f'{method} {path}: expected HTTP {status}, received {actual}')
        return body

    def issue(self, account, device):
        return self.expect('POST', '/api/v1/admin/sync-tokens', status=201, token=self.operations,
                           body={'accountId': account, 'deviceName': device})


def mutation(revision, name):
    return {'baseRevision': revision, 'deviceId': 'recovery-drill',
            'snapshot': {'syncVersion': 1, 'version': 1, 'name': name,
                         'tracks': [{'id': 'fixture-track', 'title': 'Recovery fixture'}]}}


def wait_until(predicate, message, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.025)
    raise AssertionError(message)


def snapshot_busy(data):
    try:
        with backup.FileLock(data / '.backup.snapshot.lock', timeout=0):
            return False
    except backup.BackupError:
        return True


def concurrent_snapshot(server, token, backups):
    connection = http.client.HTTPConnection('127.0.0.1', server.port, timeout=5)
    payload = json.dumps(mutation(1, 'completed-before-snapshot')).encode()
    connection.putrequest('PUT', '/api/v1/sync/library')
    connection.putheader('authorization', 'Bearer ' + token)
    connection.putheader('content-type', 'application/json')
    connection.putheader('content-length', len(payload))
    connection.endheaders()
    connection.send(payload[:1])
    entered, release = threading.Event(), threading.Event()
    real_files = backup._data_files

    def paused_files(root):
        entered.set()
        require(release.wait(10), 'Test did not release the held snapshot fence.')
        yield from real_files(root)

    try:
        wait_until(lambda: snapshot_busy(server.data), 'Upload did not acquire the native data fence.')
        with patch.object(backup, '_data_files', paused_files), ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(backup.backup, server.data, backups, timeout=5)
            try:
                wait_until(lambda: server.request('GET', '/api/v1/sync/library', token)[0] == 503,
                           'Backup intent did not prevent new data requests.')
                require(not entered.is_set(), 'Backup started reading files before the upload completed.')
                server.expect('GET', '/health')
                connection.send(payload[1:])
                response = connection.getresponse()
                result = json.loads(response.read())
                require(response.status == 200 and result['revision'] == 2, 'Admitted upload did not finish correctly.')
                require(entered.wait(5), 'Backup did not proceed after the active upload drained.')
                server.expect('GET', '/api/v1/sync/library', status=503, token=token)
                server.expect('GET', '/health')
            finally:
                release.set()
                connection.close()
            archive = pending.result(timeout=10)
        server.expect('GET', '/api/v1/sync/library', token=token)
        return archive
    finally:
        release.set()
        connection.close()


def holder(data, mode):
    return subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--hold-lock', mode, '--data', str(data)],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, creationflags=PROCESS_FLAGS)


def read_holder(process):
    with ThreadPoolExecutor(max_workers=1) as pool:
        ready = pool.submit(process.stdout.readline)
        try:
            require(ready.result(timeout=8).strip() == 'locked', 'External lock holder failed to acquire its lock.')
        except BaseException:
            process.kill()
            process.wait(timeout=5)
            raise


def stop_holder(process):
    if process.poll() is None:
        process.kill()
    process.wait(timeout=5)
    for handle in (process.stdin, process.stdout, process.stderr):
        handle.close()


def stalled_upload_times_out(server, token):
    connection = http.client.HTTPConnection('127.0.0.1', server.port, timeout=40)
    started = time.monotonic()
    try:
        connection.putrequest('PUT', '/api/v1/sync/library')
        connection.putheader('authorization', 'Bearer ' + token)
        connection.putheader('content-length', '100')
        connection.endheaders()
        connection.send(b'{')
        try:
            response = connection.getresponse()
        except http.client.RemoteDisconnected:
            # Cancelling dart:io's unfinished request body can close its socket
            # before Shelf writes the 408. Verify the actual deadline and log,
            # not merely that an arbitrary disconnect happened.
            events = [json.loads(line) for line in server.log.read_text().splitlines() if line.startswith('{')]
            require(any(event.get('statusCode') == 408 and event.get('durationMilliseconds', 0) >= 29000
                        for event in events), 'Native disconnect did not have a recorded body timeout.')
        else:
            require(response.status == 408, 'Incomplete native upload was not rejected by the production deadline.')
            require(json.loads(response.read())['error'] == 'request_body_timeout', 'Unexpected upload timeout response.')
        require(29 <= time.monotonic() - started < 38, 'Native upload did not terminate at the production body deadline.')
    finally:
        connection.close()
    wait_until(lambda: not snapshot_busy(server.data), 'Timed-out upload retained the backup fence.')


def run(executable, evidence):
    evidence.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    checks = []
    operations = secrets.token_urlsafe(32)
    with tempfile.TemporaryDirectory(prefix='aethertune-real-recovery-') as temporary:
        root = Path(temporary)
        data, backups, restored = root / 'data', root / 'backups', root / 'restored'
        with Server(executable, data, evidence / 'source-server.log', operations) as source:
            phone, desktop, other = source.issue('primary', 'Phone'), source.issue('primary', 'Desktop'), source.issue('other', 'Other')
            token, other_token = desktop['token'], other['token']
            for issued in [phone, desktop, other]:
                require_default_token_expiry(issued['device'])
            renamed = source.expect('PATCH', '/api/v1/auth/profile', token=token,
                                    body={'deviceName': 'Recovery desktop'})
            require(renamed['device']['expiresAt'] == desktop['device']['expiresAt'], 'Rename changed token expiry.')
            checks += ['default_managed_token_expiry', 'rename_preserves_token_expiry']
            source.expect('PUT', '/api/v1/sync/library', token=token, body=mutation(0, 'before-snapshot'))
            source.expect('PUT', '/api/v1/sync/library', token=other_token, body=mutation(0, 'other-account'))
            providers = {'format': 'aethertune.provider_configurations', 'version': 1,
                         'lyricsSearchEndpoint': {'format': 'aethertune.lyrics_search_endpoint', 'version': 1,
                                                  'endpoint': 'https://lyrics.example.invalid'}}
            source.expect('PUT', '/api/v1/sync/providers', token=token,
                          body={'baseRevision': 0, 'deviceId': 'desktop', 'snapshot': providers})
            source.expect('DELETE', '/api/v1/admin/sync-tokens', token=operations,
                          body={'accountId': 'primary', 'tokenId': phone['device']['id']})
            recovery = source.expect('POST', '/api/v1/admin/sync-recovery-codes', status=201, token=operations,
                                     body={'accountId': 'primary'})['recoveryCode']
            archive = concurrent_snapshot(source, token, backups)
            expected = source.expect('GET', '/api/v1/sync/library', token=token)
            expected_providers = source.expect('GET', '/api/v1/sync/providers', token=token)
            checks += ['native_cross_process_fence', 'active_upload_drained', 'new_requests_retryable_503', 'health_during_snapshot']
            stalled_upload_times_out(source, token)
            require(source.expect('GET', '/api/v1/sync/library', token=token) == expected, 'Timed-out upload changed the library.')
            checks.append('native_upload_timeout_releases_fence_without_mutation')
            source.expect('PUT', '/api/v1/sync/library', token=token, body=mutation(2, 'after-snapshot'))
            require(backup.inspect_archive(archive)['manifestVerified'], 'New archive lacks its verified manifest.')
            restore_started = time.monotonic()
            backup.restore(archive, restored)
            with Server(executable, restored, evidence / 'restored-server.log', operations) as recovered:
                require(recovered.expect('GET', '/api/v1/sync/library', token=token) == expected, 'Restored revision/checksum/payload differs.')
                require(recovered.expect('GET', '/api/v1/sync/providers', token=token) == expected_providers, 'Provider store differs after restore.')
                require(recovered.expect('GET', '/api/v1/sync/library', token=other_token)['snapshot']['name'] == 'other-account', 'Account isolation failed.')
                recovered.expect('GET', '/api/v1/sync/library', status=401, token=phone['token'])
                identity = recovered.expect('GET', '/api/v1/auth/profile', token=token)['device']
                require(identity['deviceName'] == 'Recovery desktop', 'Managed identity was not restored.')
                require(identity['expiresAt'] == desktop['device']['expiresAt'], 'Restored token expiry changed.')
                checks.append('backup_restore_preserves_token_expiry')
                recovered.expect('PUT', '/api/v1/sync/library', status=409, token=token, body=mutation(1, 'stale'))
                recovered.expect('PUT', '/api/v1/sync/library', token=token, body=mutation(2, 'after-recovery'))
                replacement = recovered.expect('POST', '/api/v1/sync/recovery', status=201,
                                               body={'recoveryCode': recovery, 'deviceName': 'Recovered'})
                redeemed = replacement['token']
                require_default_token_expiry(replacement['device'])
                renamed = recovered.expect('PATCH', '/api/v1/auth/profile', token=redeemed,
                                           body={'deviceName': 'Recovered desktop'})
                require(renamed['device']['expiresAt'] == replacement['device']['expiresAt'], 'Recovery rename changed expiry.')
                recovered.expect('GET', '/api/v1/sync/library', status=401, token=token)
                recovered.expect('POST', '/api/v1/sync/recovery', status=401,
                                 body={'recoveryCode': recovery, 'deviceName': 'Replay'})
                restored_seconds = time.monotonic() - restore_started
            with Server(executable, restored, evidence / 'restored-restart.log', operations) as restarted:
                require(restarted.expect('GET', '/api/v1/sync/library', token=redeemed)['revision'] == 3, 'Post-recovery commit did not survive process kill.')
                identity = restarted.expect('GET', '/api/v1/auth/profile', token=redeemed)['device']
                require(identity['expiresAt'] == replacement['device']['expiresAt'], 'Recovered token expiry did not survive restart.')
                require(identity['deviceName'] == 'Recovered desktop', 'Recovery device rename did not survive restart.')
                checks.append('recovery_token_expiry_survives_rename_and_restart')
                restarted.expect('GET', '/api/v1/sync/library', status=401, token=token)
                restarted.expect('POST', '/api/v1/sync/recovery', status=401,
                                 body={'recoveryCode': recovery, 'deviceName': 'Replay after restart'})
            checks += ['exact_snapshot_restore', 'provider_store_restore', 'managed_identity_restore', 'revocation_preserved',
                       'account_isolation', 'stale_revision_conflict', 'recovery_code_single_use_after_restart', 'post_restore_write_survives_kill']
            holding = holder(data, 'snapshot')
            try:
                read_holder(holding)
                source.expect('GET', '/api/v1/sync/library', status=503, token=token)
                source.expect('GET', '/health')
            finally:
                stop_holder(holding)
            source.expect('GET', '/api/v1/sync/library', token=token)
            checks.append('killed_backup_owner_releases_fence')
        with Server(executable, data, evidence / 'source-restart.log', operations) as restarted:
            require(restarted.expect('GET', '/api/v1/sync/library', token=token)['snapshot']['name'] == 'after-snapshot', 'Source write did not survive kill/restart.')
        checks.append('source_write_survives_kill')
        legacy_data = root / 'legacy'
        legacy_data.mkdir()
        holding = holder(legacy_data, 'legacy')
        try:
            read_holder(holding)
            try:
                backup.backup(legacy_data, root / 'legacy-backups', timeout=0.1)
            except backup.BackupError:
                pass
            else:
                raise AssertionError('Backup accepted an incompatible legacy lock.')
            require(not list((root / 'legacy-backups').iterdir()), 'Timed-out backup published partial output.')
        finally:
            stop_holder(holding)
        checks.append('legacy_server_lock_fails_closed')
        for log in evidence.glob('*.log'):
            content = log.read_text(encoding='utf-8')
            require(all(secret not in content for secret in [operations, phone['token'], token, other_token, recovery, redeemed]), 'Runtime logs exposed a credential.')
        checks.append('runtime_logs_do_not_expose_credentials')
    with executable.open('rb') as binary:
        binary_digest = backup._digest(binary)
    return {'result': 'passed', 'platform': platform.platform(), 'executableSha256': binary_digest,
            'backupHelperSha256': hashlib.sha256(HELPER.read_bytes()).hexdigest(),
            'sourceCommit': os.environ.get('SOURCE_COMMIT_SHA'), 'checks': checks,
            'elapsedSeconds': round(time.monotonic() - started, 3),
            'controlledRestoreAndValidationSeconds': round(restored_seconds, 3),
            'scope': 'Local controlled runtime drill; not production RPO/RTO or power-loss evidence.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path)
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--hold-lock', choices=['snapshot', 'legacy'], help=argparse.SUPPRESS)
    parser.add_argument('--data', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.hold_lock:
        lock = (backup.snapshot_lock(args.data, timeout=3) if args.hold_lock == 'snapshot'
                else backup.FileLock(args.data / '.server.lock', timeout=3))
        with lock:
            print('locked', flush=True)
            sys.stdin.read()
        return
    if args.executable is None or args.evidence is None:
        parser.error('--executable and --evidence are required')
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    report = {'result': 'failed', 'scope': 'Runtime drill did not complete.'}
    try:
        report = run(args.executable.resolve(strict=True), evidence)
        print(json.dumps(report, indent=2))
    finally:
        (evidence / 'runtime-recovery.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
