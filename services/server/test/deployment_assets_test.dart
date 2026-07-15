import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('self-hosting assets keep loopback and TLS deployment defaults',
      () async {
    final compose = await File('docker-compose.yml').readAsString();
    final systemd = await File('deploy/aethertune.service').readAsString();
    final caddy = await File('deploy/Caddyfile').readAsString();
    final environment = await File('deploy/server.env.example').readAsString();
    final dockerEnvironment = await File('.env.example').readAsString();

    expect(
      compose,
      contains(r'${AETHERTUNE_BIND_ADDRESS:-127.0.0.1}'),
    );
    expect(systemd, contains('DynamicUser=yes'));
    expect(systemd, contains('ProtectSystem=strict'));
    expect(systemd, contains('ReadWritePaths=/var/lib/aethertune'));
    expect(caddy, contains('reverse_proxy 127.0.0.1:8080'));
    expect(environment, contains("AETHERTUNE_SYNC_USERS='"));
    expect(environment, contains('AETHERTUNE_OPS_TOKEN='));
    expect(dockerEnvironment, contains('AETHERTUNE_OPS_TOKEN='));
    expect(compose, contains(r'${AETHERTUNE_OPS_TOKEN:?'));
  });
}
