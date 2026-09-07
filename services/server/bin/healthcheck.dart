import 'dart:io';

import 'package:aethertune_server/src/readiness_probe.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080');
  exitCode = port != null && await probeServerReadiness(port) ? 0 : 1;
}
