import 'dart:io';

import 'package:yaml/yaml.dart';

int verifyGraphs(Map client, Map probe) {
  if (probe.isEmpty)
    throw const FormatException('Empty probe dependency graph.');
  for (final name in probe.keys) {
    final actual = probe[name];
    final expected = client[name];
    if (actual is! Map || expected is! Map || actual['source'] != 'hosted') {
      throw FormatException('Unsupported or missing client dependency: $name');
    }
    for (final key in ['version', 'source']) {
      if (actual[key] != expected[key]) {
        throw FormatException('Probe/client $key mismatch: $name');
      }
    }
    final actualDescription = actual['description'];
    final expectedDescription = expected['description'];
    if (actualDescription is! Map || expectedDescription is! Map) {
      throw FormatException('Missing package provenance: $name');
    }
    for (final key in ['name', 'url', 'sha256']) {
      if (actualDescription[key] is! String ||
          actualDescription[key] != expectedDescription[key]) {
        throw FormatException('Probe/client $key mismatch: $name');
      }
    }
  }
  return probe.length;
}

void main() {
  final client =
      loadYaml(File('../../../apps/mobile/pubspec.lock').readAsStringSync())
          as Map;
  final probe = loadYaml(File('pubspec.lock').readAsStringSync()) as Map;
  final count = verifyGraphs(
    client['packages'] as Map,
    probe['packages'] as Map,
  );
  stdout.writeln(
    '$count probe dependencies match the client versions and provenance.',
  );
}
