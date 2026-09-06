#!/usr/bin/env python3
"""Run the native client backend through process death and optional real ENOSPC."""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def values(label, tracks=3):
    return {
        'aethertune.tracks.v1': json.dumps([
            {'id': f'{label}-{index}', 'title': f'Fixture track {index}',
             'artist': 'Storage acceptance', 'album': label, 'durationMs': 180000}
            for index in range(tracks)
        ]),
        'aethertune.playlists.v1': json.dumps([
            {'id': label, 'name': label, 'trackIds': [f'{label}-{index}' for index in range(tracks)]}
        ]),
        'aethertune.onboarding_completed.v1': True,
    }


class Probe:
    def __init__(self, executable, directory, log, *, user=None):
        self.log = log
        self.errors = log.open('w', encoding='utf-8')
        self.events = queue.Queue()
        self.maximum_rss = 0
        options = {} if user is None else {'user': user, 'group': user, 'extra_groups': []}
        try:
            self.process = subprocess.Popen(
                [str(executable), str(directory)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=self.errors, text=True,
                encoding='utf-8', bufsize=1, **options,
            )
        except BaseException:
            self.errors.close()
            raise
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            ready = self.event('ready')
            require(ready['pid'] == self.process.pid, 'Probe did not identify its actual process')
        except BaseException:
            self.close()
            raise

    def _read(self):
        try:
            for line in self.process.stdout:
                self.events.put(json.loads(line))
        except (OSError, ValueError) as error:
            self.events.put({'event': 'protocol_error', 'error': str(error)})
        finally:
            self.events.put({'event': 'eof'})

    def event(self, expected, timeout=15):
        try:
            event = self.events.get(timeout=timeout)
        except queue.Empty:
            raise AssertionError(f'Probe deadline exceeded waiting for {expected}') from None
        require(event.get('event') == expected, f'Expected {expected}, received {event}')
        self.maximum_rss = max(self.maximum_rss, event.get('max_rss_bytes', 0))
        return event

    def start(self, operation, **fields):
        self.process.stdin.write(json.dumps({'operation': operation, **fields}) + '\n')
        self.process.stdin.flush()
        self.event('started')

    def request(self, operation, expected, **fields):
        self.start(operation, **fields)
        return self.event(expected)

    def resume(self):
        self.process.stdin.write('continue\n')
        self.process.stdin.flush()

    def require_waiting(self):
        try:
            event = self.events.get(timeout=0.3)
        except queue.Empty:
            require(self.process.poll() is None, 'Blocked writer exited unexpectedly')
            return
        raise AssertionError(f'Writer bypassed the held storage lock: {event}')

    def kill(self):
        require(self.process.poll() is None, 'Cannot prove interruption of an already exited process')
        self.process.kill()
        require(self.process.wait(timeout=5) != 0, 'Killed probe unexpectedly exited successfully')

    def close(self):
        forced = False
        try:
            if self.process.poll() is None:
                self.process.stdin.close()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    forced = True
                    self.process.kill()
                    self.process.wait(timeout=5)
        finally:
            self.process.stdin.close()
            self.reader.join(timeout=5)
            self.process.stdout.close()
            self.errors.close()
        require(not self.reader.is_alive(), 'Probe output reader failed to finish')
        require(not forced, 'Probe needed forced cleanup after a test')


class Fixture:
    def __init__(self, executable, evidence):
        self.executable = executable
        self.evidence = evidence
        self.probes = []

    def open(self, directory, *, user=None):
        probe = Probe(self.executable, directory, self.evidence / f'probe-{len(self.probes)}.log', user=user)
        self.probes.append(probe)
        return probe

    def cleanup(self):
        errors = []
        for probe in reversed(self.probes):
            try:
                probe.close()
            except (OSError, AssertionError, subprocess.SubprocessError) as error:
                errors.append(str(error))
        return errors


def read_saved(probe, expected_values, expected_revision=None):
    result = probe.request('read', 'read')
    require(result['values'] == expected_values, 'Reopened library did not match all expected sections')
    if expected_revision is not None:
        require(result['revision'] == expected_revision, 'A failed operation changed the saved revision')
    return result['revision']


def seed(probe):
    first = probe.request('write', 'committed', values=values('previous'), revision=None)['revision']
    return probe.request('write', 'committed', values=values('current'), revision=first)['revision']


def saved_bytes(directory):
    return {name: (directory / name).read_bytes() for name in ('library.json', 'library.previous.json')}


def process_acceptance(fixture, directory, checks, metrics):
    directory.mkdir()
    original = fixture.open(directory)
    revision = seed(original)
    expected = saved_bytes(directory)
    original.kill()
    current = fixture.open(directory)
    read_saved(current, values('current'), revision)
    checks.append('acknowledged_commit_survives_process_kill')

    current.request('write', 'pending_flushed', values=values('interrupted'), revision=revision, pause=True)
    current.kill()
    require(saved_bytes(directory) == expected, 'Pre-commit process death changed a committed snapshot')
    require((directory / 'library.pending').stat().st_size > 0, 'Interrupted write did not reach real flushed bytes')
    writer = fixture.open(directory)
    read_saved(writer, values('current'), revision)
    checks.append('killed_pending_write_preserves_current_and_previous')

    writer.request('write', 'pending_flushed', values=values('winner'), revision=revision, pause=True)
    stale = fixture.open(directory)
    stale.start('write', values=values('stale'), revision=revision)
    stale.require_waiting()
    writer.resume()
    revision = writer.event('committed')['revision']
    stale.event('conflict')
    read_saved(stale, values('winner'), revision)
    checks.append('cross_process_stale_writer_waits_then_conflicts')

    writer.request('write', 'pending_flushed', values=values('killed-holder'), revision=revision, pause=True)
    waiter = fixture.open(directory)
    waiter.start('write', values=values('after-kill'), revision=revision)
    waiter.require_waiting()
    writer.kill()
    revision = waiter.event('committed')['revision']
    read_saved(waiter, values('after-kill'), revision)
    checks.append('process_death_releases_native_sqlite_lock')

    previous = json.loads(json.loads((directory / 'library.previous.json').read_text())['payload'])
    (directory / 'library.json').write_bytes(b'{fixture-corruption')
    waiter.request('read', 'error')
    require((directory / 'library.json').read_bytes() == b'{fixture-corruption', 'Read silently replaced corrupt data')
    waiter.request('recover_previous', 'recovered')
    revision = read_saved(waiter, previous)
    archives = list((directory / 'recovery').glob('*/library.json'))
    require(len(archives) == 1 and archives[0].read_bytes() == b'{fixture-corruption', 'Recovery lost original corrupt bytes')
    checks.append('native_corruption_requires_explicit_archived_recovery')

    large = values('large', 25000)
    started = time.monotonic()
    revision = waiter.request('write', 'committed', values=large, revision=revision)['revision']
    elapsed = time.monotonic() - started
    waiter.kill()
    reopened = fixture.open(directory)
    read_saved(reopened, large, revision)
    metrics.update({'large_library_tracks': 25000, 'large_snapshot_bytes': (directory / 'library.json').stat().st_size,
                    'large_write_seconds': round(elapsed, 4),
                    'maximum_probe_rss_bytes': max(probe.maximum_rss for probe in fixture.probes)})
    require(metrics['maximum_probe_rss_bytes'] > 0, 'Probe did not report native memory usage')
    checks.append('large_snapshot_reopens_after_process_kill')

    migration = directory.parent / 'initial-commit'
    migration.mkdir()
    initial = fixture.open(migration)
    initial.request('write', 'pending_flushed', values=values('initial'), revision=None, pause=True)
    initial.kill()
    resumed = fixture.open(migration)
    empty = resumed.request('read', 'read')
    require(empty['values'] is None and empty['revision'] is None, 'Uncommitted initial data was treated as saved')
    revision = resumed.request('write', 'committed', values=values('initial'), revision=None)['revision']
    read_saved(resumed, values('initial'), revision)
    checks.append('interrupted_initial_commit_can_retry_without_false_success')


def fill_filesystem(path):
    written = 0
    with path.open('wb', buffering=0) as stream:
        try:
            while written <= 16 * 1024 * 1024:
                written += stream.write(b'F' * (64 * 1024))
        except OSError as error:
            require(error.errno == errno.ENOSPC, f'Expected real ENOSPC, got {error}')
        else:
            raise AssertionError('Disposable filesystem was not bounded to its expected size')
    require(os.statvfs(path).f_bavail == 0, 'Filesystem did not actually reach zero available blocks')
    return written


def disk_acceptance(fixture, directory, checks, metrics):
    require(sys.platform == 'linux' and os.geteuid() == 0, 'Disk acceptance requires Linux root in a private mount namespace')
    require(os.readlink('/proc/self/ns/mnt') != os.readlink('/proc/1/ns/mnt'), 'Refusing mounts in the host init mount namespace')
    directory.mkdir()
    mounted = False
    disk_probes = []
    try:
        subprocess.run(['mount', '-t', 'tmpfs', '-o', 'size=8m,mode=0700,nosuid,nodev,noexec',
                        'aethertune-storage-fixture', str(directory)], check=True, timeout=10)
        mounted = True
        require(os.statvfs(directory).f_blocks * os.statvfs(directory).f_frsize <= 8 * 1024 * 1024,
                'Disposable filesystem exceeded its size limit')
        os.chown(directory, 65534, 65534)
        for phase in ('full_before_lock', 'previous_write', 'partial_pending_write'):
            case = directory / phase
            case.mkdir(mode=0o700)
            os.chown(case, 65534, 65534)
            writer = fixture.open(case, user=65534)
            disk_probes.append(writer)
            revision = seed(writer)
            expected = saved_bytes(case)
            if phase == 'previous_write':
                writer.request('write', 'pending_flushed', values=values('unsaved'), revision=revision, pause=True)
            filler = case / 'fixture-filler'
            used = fill_filesystem(filler)
            if phase == 'previous_write':
                writer.resume()
                failure = writer.event('filesystem_error')
            else:
                if phase == 'partial_pending_write':
                    with filler.open('r+b', buffering=0) as stream:
                        stream.truncate(used - 64 * 1024)
                failure = writer.request('write', 'sqlite_error' if phase == 'full_before_lock' else 'filesystem_error',
                                         values=values('unsaved', 10000), revision=revision)
            expected_code = 13 if phase == 'full_before_lock' else errno.ENOSPC
            require(failure['code'] == expected_code, f'Backend did not report the expected full-storage error: {failure}')
            metrics[phase + '_error'] = failure
            require(saved_bytes(case) == expected, f'{phase}: failed write changed committed data')
            if phase == 'partial_pending_write':
                require(0 < (case / 'library.pending').stat().st_size <= 64 * 1024,
                        'Partial-write test did not actually leave partial pending bytes')
            writer.kill()
            filler.unlink()
            reader = fixture.open(case, user=65534)
            disk_probes.append(reader)
            read_saved(reader, values('current'), revision)
            revision = reader.request('write', 'committed', values=values('retry'), revision=revision)['revision']
            read_saved(reader, values('retry'), revision)
            require((case / 'library.json').stat().st_uid == 65534, 'Storage was not exercised as the unprivileged fixture user')
            checks.append(f'actual_enospc_{phase}_preserves_data_and_retries')
            metrics[phase + '_filler_bytes'] = used
    finally:
        errors = []
        try:
            for probe in disk_probes:
                try:
                    probe.close()
                except (OSError, AssertionError, subprocess.SubprocessError) as error:
                    errors.append(str(error))
        finally:
            if mounted:
                subprocess.run(['umount', str(directory)], check=True, timeout=10)
        require(not errors, f'Disk fixture process cleanup failed: {errors}')


def run(executable, evidence, disk_full=False):
    executable = executable.resolve(strict=True)
    evidence = evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    checks, metrics = [], {}
    report = {'result': 'failed', 'platform': sys.platform, 'executable_sha256': digest(executable),
              'backend_sha256': digest(ROOT / 'apps/mobile/lib/src/data/file_library_storage.dart'),
              'probe_lock_sha256': digest(ROOT / 'scripts/ci/library_storage_probe/pubspec.lock'),
              'source_commit': os.environ.get('GITHUB_SHA'), 'checks': checks, 'metrics': metrics,
              'disk_full_requested': disk_full,
              'scope': 'native production file backend; not installed Flutter, power loss, or physical disk failure'}
    fixture = Fixture(executable, evidence)
    try:
        with tempfile.TemporaryDirectory(prefix='aethertune-storage-') as temporary:
            root = Path(temporary)
            if disk_full:
                root.chmod(0o755)
            try:
                process_acceptance(fixture, root / 'library', checks, metrics)
                if disk_full:
                    disk_acceptance(fixture, root / 'bounded', checks, metrics)
            finally:
                errors = fixture.cleanup()
                report['cleanup_errors'] = errors
                require(not errors, f'Fixture cleanup failed: {errors}')
        report['result'] = 'passed'
    except (OSError, ValueError, KeyError, AssertionError, subprocess.SubprocessError) as error:
        report['error'] = str(error)
    (evidence / 'runtime.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report['result'] == 'passed' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--disk-full', action='store_true', help='Also run bounded tmpfs ENOSPC acceptance in a private Linux mount namespace')
    arguments = parser.parse_args()
    raise SystemExit(run(arguments.executable, arguments.evidence, arguments.disk_full))
