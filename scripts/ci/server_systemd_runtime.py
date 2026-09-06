#!/usr/bin/env python3
"""Exercise isolated copies of the real systemd units, then remove all fixtures."""

import argparse
import configparser
import hashlib
import http.client
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / 'services/server/deploy'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def command(*arguments, check=True):
    result = subprocess.run(list(map(str, arguments)), text=True, capture_output=True, timeout=45)
    if check and result.returncode:
        raise RuntimeError(f'{arguments[0]} {arguments[1]} failed: {result.stderr.strip()}')
    return result.stdout.strip()


def properties(unit, *names):
    output = command('systemctl', 'show', unit, *[f'--property={name}' for name in names])
    return dict(line.split('=', 1) for line in output.splitlines() if '=' in line)


def unit_config(source, overrides):
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read(source, encoding='utf-8')
    for section, values in overrides.items():
        for name, value in values.items():
            require(name in config[section], f'Unexpected unit structure: {section}.{name}')
            config[section][name] = value
    return config


class Client:
    def __init__(self, port):
        self.port = port

    def request(self, method, path, *, token=None, body=None, status=200):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        try:
            headers = {'content-type': 'application/json'}
            if token:
                headers['authorization'] = 'Bearer ' + token
            connection.request(method, path, None if body is None else json.dumps(body), headers)
            response = connection.getresponse()
            raw = response.read()
            require(response.status == status, f'{method} {path}: HTTP {response.status}, expected {status}')
            return json.loads(raw) if raw else None
        finally:
            connection.close()

    def ready(self, unit):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            state = properties(unit, 'ActiveState', 'MainPID')
            require(state['ActiveState'] in ('active', 'activating'), 'Service did not stay active.')
            try:
                self.request('GET', '/ready')
                return int(state['MainPID'])
            except (OSError, http.client.HTTPException):
                time.sleep(0.05)
        raise AssertionError('Service readiness timed out.')


def mutation(revision, name):
    return {'baseRevision': revision, 'deviceId': 'systemd-drill',
            'snapshot': {'syncVersion': 1, 'version': 1, 'name': name, 'tracks': []}}


def run(executable, evidence):
    require(sys.platform == 'linux' and os.geteuid() == 0, 'Run as root on a Linux systemd test host.')
    command('systemctl', 'show', '--property=Version')
    identity = 'aethertune-readiness-' + uuid.uuid4().hex
    assets = Path('/run') / identity
    data = Path('/var/lib') / identity
    private_data = Path('/var/lib/private') / identity
    units = [identity + '.service', identity + '-backup.service']
    unit_paths = [Path('/run/systemd/system') / unit for unit in units]
    for path in [assets, data, private_data, *unit_paths]:
        require(not path.exists() and not path.is_symlink(), f'Fixture path already exists: {path}')
    evidence.mkdir(parents=True, exist_ok=True)
    assets.mkdir(mode=0o755)
    assets.chmod(0o755)
    backups = assets / 'backups'
    backups.mkdir(mode=0o700)
    installed_units = []
    original = None
    credentials = []
    report = {'result': 'failed', 'fixture': identity, 'checks': [],
              'scope': 'Isolated systemd deployment fixture; not production load or RPO/RTO.'}
    try:
        shutil.copyfile(executable, assets / 'server')
        (assets / 'server').chmod(0o755)
        for name in ('aethertune-backup.py', 'aethertune-backup.sh', 'aethertune-restore.sh'):
            shutil.copyfile(DEPLOY / name, assets / name)
            (assets / name).chmod(0o644 if name.endswith('.py') else 0o755)
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        operations = secrets.token_urlsafe(32)
        credentials.append(operations)
        environment = assets / 'server.env'
        environment.write_text(f'AETHERTUNE_OPS_TOKEN={operations}\nAETHERTUNE_SYNC_USERS={{}}\n'
                               f'AETHERTUNE_LISTEN_ADDRESS=127.0.0.1\nPORT={port}\n', encoding='utf-8')
        environment.chmod(0o600)
        configs = [
            unit_config(DEPLOY / 'aethertune.service', {'Service': {
                'StateDirectory': identity, 'EnvironmentFile': str(environment),
                'Environment': f'AETHERTUNE_DATA_DIR={data}', 'ExecStart': str(assets / 'server'),
                'ReadWritePaths': str(data)}}),
            unit_config(DEPLOY / 'aethertune-backup.service', {
                'Unit': {'After': units[0], 'Requires': units[0]},
                'Service': {'EnvironmentFile': str(environment),
                            'ExecStart': f'{assets}/aethertune-backup.sh {data} {backups}',
                            'ReadWritePaths': f'{backups} {data}'}}),
        ]
        for path, config in zip(unit_paths, configs):
            with path.open('x', encoding='utf-8') as output:
                config.write(output, space_around_delimiters=False)
            path.chmod(0o644)
            installed_units.append(path)
        command('systemctl', 'daemon-reload')
        command('systemctl', 'start', units[0])
        client = Client(port)
        pid = client.ready(units[0])
        uid = Path(f'/proc/{pid}').stat().st_uid
        require(uid != 0, 'Server unexpectedly runs as root.')
        sandbox = properties(units[0], 'DynamicUser', 'NoNewPrivileges', 'ProtectSystem',
                             'PrivateDevices', 'ProtectHome', 'RestrictAddressFamilies')
        require(sandbox['DynamicUser'] == 'yes' and sandbox['NoNewPrivileges'] == 'yes'
                and sandbox['ProtectSystem'] == 'strict', 'Production sandbox is not active.')
        report.update(serviceUid=uid, sandbox=sandbox,
                      systemdVersion=command('systemctl', '--version').splitlines()[0])
        report['checks'].append('real_unit_starts_with_dynamic_user_and_sandbox')

        def issue(device):
            value = client.request('POST', '/api/v1/admin/sync-tokens', token=operations,
                                   body={'accountId': 'fixture', 'deviceName': device}, status=201)
            credentials.append(value['token'])
            return value

        old, active = issue('Revoked'), issue('Active')
        token = active['token']
        client.request('DELETE', '/api/v1/admin/sync-tokens', token=operations,
                       body={'accountId': 'fixture', 'tokenId': old['device']['id']})
        client.request('PUT', '/api/v1/sync/library', token=token, body=mutation(0, 'saved-before-backup'))
        expected = client.request('GET', '/api/v1/sync/library', token=token)
        command('systemctl', 'start', units[1])
        require(properties(units[1], 'Result')['Result'] == 'success', 'Sandboxed backup failed.')
        archives = list(backups.glob('*.tar.gz'))
        require(len(archives) == 1, 'Backup did not publish exactly one archive.')
        report['checks'].append('root_backup_unit_reads_dynamic_user_state')
        client.request('PUT', '/api/v1/sync/library', token=token, body=mutation(1, 'after-backup'))
        command('systemctl', 'stop', units[0])
        require(properties(units[0], 'MainPID')['MainPID'] == '0', 'Server did not stop before restore.')
        physical = data.resolve(strict=True)
        require(physical in (data, private_data), 'Unexpected systemd state-directory location.')
        owner = physical.stat()
        original = physical.with_name(identity + '-before-restore')
        require(not original.exists(), 'Restore fixture already exists.')
        physical.rename(original)
        command(assets / 'aethertune-restore.sh', archives[0], physical)
        for directory, names, files in os.walk(physical):
            for name in [None, *files]:
                item = Path(directory) if name is None else Path(directory) / name
                require(not item.is_symlink(), 'Unexpected link in restored data.')
                os.chown(item, owner.st_uid, owner.st_gid, follow_symlinks=False)
        command('systemctl', 'start', units[0])
        client.ready(units[0])
        require(client.request('GET', '/api/v1/sync/library', token=token) == expected,
                'Restored service differs from the backed-up snapshot.')
        client.request('GET', '/api/v1/sync/library', token=old['token'], status=401)
        client.request('PUT', '/api/v1/sync/library', token=token, body=mutation(1, 'after-restore'))
        report['checks'] += ['restore_ownership_allows_dynamic_user_restart', 'exact_snapshot_restored',
                             'revoked_token_remains_rejected', 'restored_service_accepts_writes']
        command('systemctl', 'restart', units[0])
        client.ready(units[0])
        require(client.request('GET', '/api/v1/sync/library', token=token)['revision'] == 2,
                'Post-restore write did not persist across systemd restart.')
        command('systemctl', 'start', units[1])
        require(properties(units[1], 'Result')['Result'] == 'success', 'Backup after restore failed.')
        report['checks'] += ['post_restore_write_survives_systemd_restart', 'backup_after_restore_succeeds']
        report['result'] = 'passed'
    finally:
        cleanup_errors = []
        for unit in reversed(units):
            if Path('/run/systemd/system', unit) not in installed_units:
                continue
            try:
                command('systemctl', 'stop', unit)
                require(properties(unit, 'MainPID')['MainPID'] == '0', 'Fixture process still running.')
                log = command('journalctl', '--unit', unit, '--no-pager', '--output=cat', check=False)
                exposed = any(secret in log for secret in credentials)
                for secret in credentials:
                    log = log.replace(secret, '[redacted]')
                (evidence / (unit + '.log')).write_text(log + '\n', encoding='utf-8')
                require(not exposed, 'Service journal exposed a fixture credential.')
            except Exception as error:
                cleanup_errors.append(str(error))
        if not cleanup_errors:
            try:
                if unit_paths[0] in installed_units:
                    command('systemctl', 'clean', '--what=state', units[0])
                if original is not None and original.exists():
                    require(original.parent in (data.parent, private_data.parent)
                            and original.name == identity + '-before-restore', 'Unsafe cleanup path.')
                    shutil.rmtree(original)
                for path in installed_units:
                    path.unlink()
                command('systemctl', 'daemon-reload')
                require(assets.parent == Path('/run') and assets.name == identity, 'Unsafe fixture path.')
                shutil.rmtree(assets)
                require(not data.exists() and not private_data.exists(), 'Fixture state was not cleaned.')
            except Exception as error:
                cleanup_errors.append(str(error))
        report['cleanupErrors'] = cleanup_errors
        report['sourceCommit'] = os.environ.get('SOURCE_COMMIT_SHA')
        report['executableSha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
        report['deploymentSha256'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                      for path in DEPLOY.iterdir() if path.is_file()}
        if cleanup_errors:
            report['result'] = 'failed'
        (evidence / 'systemd-runtime.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        require(not cleanup_errors, f'Fixture cleanup failed: {cleanup_errors}; inspect {identity}.')
    require(report['result'] == 'passed', 'Systemd runtime validation failed.')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    run(args.executable.resolve(strict=True), args.evidence.resolve())
