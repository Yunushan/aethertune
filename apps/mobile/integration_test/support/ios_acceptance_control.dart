import 'dart:convert';

import 'package:path/path.dart' as p;

String iosAcceptancePhase({
  required String controlJson,
  required String supportPath,
  required String device,
  required String fixtureName,
  required String source,
}) {
  const uuid =
      r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}';
  if (!RegExp('^$uuid\$').hasMatch(device) ||
      !RegExp(r'^AetherTune_Acceptance_[0-9a-f]{32}$').hasMatch(fixtureName) ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(source)) {
    throw const FormatException('Invalid compiled iOS fixture identity.');
  }
  final container = RegExp(
    '^/.+/CoreSimulator/Devices/${RegExp.escape(device)}/data/'
    'Containers/Data/Application/$uuid/Library/Application Support\$',
  );
  if (p.posix.normalize(supportPath) != supportPath ||
      !container.hasMatch(supportPath)) {
    throw const FormatException(
      'Not the compiled fixture Simulator app container.',
    );
  }
  final control = jsonDecode(controlJson);
  if (control is! Map<String, dynamic> ||
      control['device'] != device ||
      control['fixtureName'] != fixtureName ||
      control['sourceCommit'] != source ||
      !const ['seed', 'reopen', 'sync'].contains(control['phase'])) {
    throw const FormatException(
      'Missing or mismatched iOS acceptance control.',
    );
  }
  return control['phase'] as String;
}
