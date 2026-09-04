import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:test/test.dart';

void main() {
  test('self-hosting assets keep loopback and TLS deployment defaults', () async {
    final compose = await File('docker-compose.yml').readAsString();
    final dockerfile = await File('Dockerfile').readAsString();
    final systemd = await File('deploy/aethertune.service').readAsString();
    final backup = await File('deploy/aethertune-backup.sh').readAsString();
    final opsProbe = await File(
      'deploy/aethertune-ops-probe.sh',
    ).readAsString();
    final rollback = await File('deploy/aethertune-rollback.sh').readAsString();
    final verifyBackups = await File(
      'deploy/aethertune-verify-backups.sh',
    ).readAsString();
    final restore = await File('deploy/aethertune-restore.sh').readAsString();
    final backupService = await File(
      'deploy/aethertune-backup.service',
    ).readAsString();
    final backupTimer = await File(
      'deploy/aethertune-backup.timer',
    ).readAsString();
    final backupVerifyService = await File(
      'deploy/aethertune-backup-verify.service',
    ).readAsString();
    final backupVerifyTimer = await File(
      'deploy/aethertune-backup-verify.timer',
    ).readAsString();
    final caddy = await File('deploy/Caddyfile').readAsString();
    final environment = await File('deploy/server.env.example').readAsString();
    final dockerEnvironment = await File('.env.example').readAsString();

    expect(compose, contains(r'${AETHERTUNE_BIND_ADDRESS:-127.0.0.1}'));
    expect(systemd, contains('DynamicUser=yes'));
    expect(systemd, contains('ProtectSystem=strict'));
    expect(systemd, contains('ReadWritePaths=/var/lib/aethertune'));
    expect(systemd, contains('RestrictAddressFamilies=AF_INET AF_INET6'));
    expect(systemd, contains('PrivateDevices=yes'));
    expect(opsProbe, contains('BASE_URL must use HTTPS'));
    expect(opsProbe, contains('/health'));
    expect(opsProbe, contains('/ready'));
    expect(opsProbe, contains('/api/v1/metrics'));
    expect(opsProbe, contains('responses5xx'));
    expect(caddy, contains('reverse_proxy 127.0.0.1:8080'));
    expect(caddy, contains('Strict-Transport-Security'));
    expect(caddy, contains('X-Content-Type-Options "nosniff"'));
    expect(caddy, contains('X-Frame-Options "DENY"'));
    expect(caddy, contains('Referrer-Policy "no-referrer"'));
    expect(environment, contains("AETHERTUNE_SYNC_USERS='{}'"));
    expect(environment, contains('AETHERTUNE_OPS_TOKEN='));
    expect(dockerEnvironment, contains('AETHERTUNE_SYNC_USERS={}'));
    expect(dockerEnvironment, contains('AETHERTUNE_OPS_TOKEN='));
    expect(dockerEnvironment, contains('AETHERTUNE_LISTEN_ADDRESS=0.0.0.0'));
    expect(environment, contains('AETHERTUNE_LISTEN_ADDRESS=127.0.0.1'));
    expect(compose, contains(r'${AETHERTUNE_OPS_TOKEN:?'));
    expect(compose, contains(r'${AETHERTUNE_LISTEN_ADDRESS:-0.0.0.0}'));
    expect(compose, contains('read_only: true'));
    expect(compose, contains('cap_drop:'));
    expect(compose, contains('no-new-privileges:true'));
    expect(compose, contains('stop_grace_period: 30s'));
    expect(compose, contains('cpus:'));
    expect(compose, contains('memory:'));
    expect(compose, contains('http://127.0.0.1:8080/ready'));
    expect(caddy, contains('sync.example.com {'));
    expect(caddy, contains('encode zstd gzip'));
    expect(
      caddy,
      contains(
        'Strict-Transport-Security "max-age=31536000; includeSubDomains"',
      ),
    );
    expect(caddy, contains('-Server'));
    expect(
      dockerfile,
      matches(RegExp(
        r'FROM dart:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64} AS build',
      )),
    );
    expect(
      dockerfile,
      matches(RegExp(r'FROM debian:bookworm-slim@sha256:[0-9a-f]{64}')),
    );
    expect(dockerfile, contains('dart pub get --enforce-lockfile'));
    expect(dockerfile, contains('RUN mkdir -p /out'));
    expect(dockerfile, contains('http://127.0.0.1:8080/ready'));
    expect(backup, contains("--exclude='*.tmp'"));
    expect(backup, contains("--exclude='$serverDataDirectoryLockFileName'"));
    expect(backup, contains(r'sha256sum "$(basename "$archive")"'));
    expect(backup, contains('sha256sum --check'));
    expect(rollback, contains('install -m 0755'));
    expect(rollback, contains(r'mv -f "$temporary_path"'));
    expect(
      rollback,
      contains('Current and previous binaries must be different paths'),
    );
    expect(verifyBackups, contains('sha256sum --check'));
    expect(verifyBackups, contains('tar -tzf'));
    expect(verifyBackups, contains('Missing checksum sidecar'));
    expect(restore, contains('Unsafe archive entry'));
    expect(restore, contains('tar -tvzf'));
    expect(restore, contains('Unsafe archive entry type'));
    expect(restore, contains('Missing checksum sidecar'));
    expect(restore, contains('archive_dir='));
    expect(restore, contains(r'sha256sum --check "$checksum_name"'));
    expect(backupService, contains('aethertune-backup.sh'));
    expect(backupService, contains('ProtectSystem=strict'));
    expect(backupService, contains('ReadWritePaths=/var/backups/aethertune'));
    expect(backupService, contains('RestrictAddressFamilies=AF_UNIX'));
    expect(backupTimer, contains('Persistent=true'));
    expect(
      backupVerifyService,
      contains(
        'ExecStart=/usr/local/libexec/aethertune-verify-backups.sh /var/backups/aethertune',
      ),
    );
    expect(
      backupVerifyService,
      contains('ReadOnlyPaths=/var/backups/aethertune'),
    );
    expect(backupVerifyService, contains('Requires=aethertune-backup.service'));
    expect(backupVerifyTimer, contains('OnCalendar=*-*-* 04:00:00'));
    expect(backupVerifyTimer, contains('Persistent=true'));
  });
}
