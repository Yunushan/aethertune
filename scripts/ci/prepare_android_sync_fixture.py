#!/usr/bin/env python3
"""Prepare/remove a synthetic TLS trust fixture in a disposable Android AVD only."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'dev.aethertune.aethertune'
GUEST_INPUT = 'files/android-sync-fixture'
GUEST_CA = '/data/misc/user/0/cacerts-added'
MARKER = b'aethertune-android-sync-acceptance-v1\n'


def run(args: list[str], *, data: bytes | None = None, check: bool = True) -> bytes:
    result = subprocess.run(args, input=data, capture_output=True, timeout=60)
    if check and result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args!r}: '
                           f'{result.stderr.decode(errors="replace")}')
    return result.stdout


def validate_target(adb: str, serial: str, avd: str) -> list[str]:
    if not re.fullmatch(r'emulator-\d+', serial):
        raise ValueError('Only an explicit emulator serial may be used.')
    if not re.fullmatch(r'AetherTune_Acceptance_[A-Za-z0-9_]+', avd):
        raise ValueError('Only a named AetherTune disposable acceptance AVD may be used.')
    command = [adb, '-s', serial]
    for name, expected in [('ro.kernel.qemu', '1'), ('ro.boot.qemu.avd_name', avd),
                           ('ro.build.type', 'userdebug')]:
        actual = run(command + ['shell', 'getprop', name]).decode().strip()
        if actual != expected:
            raise ValueError(f'Disposable AVD identity mismatch: {name}={actual!r}')
    return command


def validate_output(output: Path) -> Path:
    output = output.resolve()
    if not output.is_relative_to((ROOT / 'build').resolve()) or output == (ROOT / 'build').resolve():
        raise ValueError('Fixture output must be inside the repository build directory.')
    return output


def root_adb(command: list[str]) -> None:
    run(command + ['root'])
    run(command + ['wait-for-device'])
    if run(command + ['shell', 'id', '-u']).strip() != b'0':
        raise RuntimeError('AOSP userdebug root service is required inside this disposable AVD.')


def prepare(adb: str, openssl: str, serial: str, avd: str, output: Path) -> None:
    output = validate_output(output)
    command = validate_target(adb, serial, avd)
    output.mkdir(parents=True, exist_ok=False)
    for name in ('trusted', 'untrusted'):
        ca = str(output / f'{name}-ca')
        leaf = str(output / f'{name}-leaf')
        run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', ca + '.key',
             '-out', ca + '.pem', '-days', '2', '-subj', f'/CN=AetherTune Synthetic Android {name} CA',
             '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign'])
        run([openssl, 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', leaf + '.key',
             '-out', leaf + '.csr', '-subj', '/CN=127.0.0.1'])
        run([openssl, 'x509', '-req', '-in', leaf + '.csr', '-CA', ca + '.pem', '-CAkey', ca + '.key',
             '-set_serial', '1', '-out', leaf + '.pem', '-days', '2', '-extfile',
             str(ROOT / 'scripts/ci/testdata/sync_transport_leaf.ext')])
    certificate = output / 'trusted-ca.pem'
    name = run([openssl, 'x509', '-in', str(certificate), '-subject_hash_old', '-noout']).decode().strip()
    if not re.fullmatch('[0-9a-f]{8}', name):
        raise RuntimeError('Invalid certificate subject hash.')
    guest_certificate = f'{GUEST_CA}/{name}.0'
    root_adb(command)
    exists = run(command + ['shell', 'sh', '-c', f'"if test -e {guest_certificate}; then echo exists; fi"'])
    if exists.strip():
        raise RuntimeError('Refusing to overwrite an existing guest root certificate.')
    receipt = {'serial': serial, 'avd': avd, 'guest_certificate': guest_certificate,
               'certificate_sha256': hashlib.sha256(certificate.read_bytes()).hexdigest()}
    # Persist ownership before the first trust mutation, so partial setup can be cleaned up.
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    run(command + ['shell', 'mkdir', '-p', GUEST_CA])
    run(command + ['shell', 'chown', 'system:system', GUEST_CA])
    run(command + ['shell', 'chmod', '755', GUEST_CA])
    run(command + ['push', str(certificate), guest_certificate])
    run(command + ['shell', 'chown', 'system:system', guest_certificate])
    run(command + ['shell', 'chmod', '644', guest_certificate])
    run(command + ['shell', 'restorecon', '-R', GUEST_CA])
    run(command + ['shell', 'run-as', PACKAGE, 'mkdir', '-p', GUEST_INPUT])
    for name in ('trusted-ca.pem', 'trusted-leaf.pem', 'trusted-leaf.key',
                 'untrusted-leaf.pem', 'untrusted-leaf.key'):
        run(command + ['shell', '-T', 'run-as', PACKAGE, 'tee', f'{GUEST_INPUT}/{name}'],
            data=(output / name).read_bytes())
    run(command + ['shell', '-T', 'run-as', PACKAGE, 'tee', f'{GUEST_INPUT}/marker'], data=MARKER)
    run(command + ['shell', 'am', 'force-stop', PACKAGE])
    print(f'Prepared synthetic guest-only TLS fixture: {output}')


def cleanup(adb: str, serial: str, avd: str, output: Path) -> None:
    output = validate_output(output)
    command = validate_target(adb, serial, avd)
    receipt = json.loads((output / 'receipt.json').read_text(encoding='utf-8'))
    path = receipt['guest_certificate']
    if receipt['serial'] != serial or receipt['avd'] != avd or not re.fullmatch(
            re.escape(GUEST_CA) + r'/[0-9a-f]{8}\.0', path):
        raise ValueError('Fixture receipt does not match the disposable guest.')
    root_adb(command)
    content = run(command + ['exec-out', 'cat', path])
    if hashlib.sha256(content).hexdigest() != receipt['certificate_sha256']:
        raise ValueError('Guest certificate differs from this fixture; refusing removal.')
    run(command + ['shell', 'rm', path])
    run(command + ['shell', 'am', 'force-stop', PACKAGE])
    # Remove only named generated inputs, never recursively delete an app profile.
    for name in ('trusted-ca.pem', 'trusted-leaf.pem', 'trusted-leaf.key',
                 'untrusted-leaf.pem', 'untrusted-leaf.key', 'marker'):
        run(command + ['shell', 'run-as', PACKAGE, 'rm', '-f', f'{GUEST_INPUT}/{name}'])
    run(command + ['unroot'])
    run(command + ['wait-for-device'])
    if run(command + ['shell', 'id', '-u']).strip() == b'0':
        raise RuntimeError('Guest ADB root is still active after cleanup.')
    (output / 'cleanup.json').write_text(json.dumps({'status': 'passed', **receipt}, indent=2) + '\n', encoding='utf-8')
    print('Removed the owned synthetic root and app fixture; disabled guest ADB root.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'cleanup'])
    parser.add_argument('--adb', required=True)
    parser.add_argument('--openssl')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--avd', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.action == 'prepare':
        if not args.openssl:
            parser.error('--openssl is required to prepare certificates')
        prepare(args.adb, args.openssl, args.serial, args.avd, args.output)
    else:
        cleanup(args.adb, args.serial, args.avd, args.output)


if __name__ == '__main__':
    main()
