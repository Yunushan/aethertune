import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/ios_acceptance_control.dart';

void main() {
  const device = '11111111-2222-4333-8444-555555555555';
  const fixtureName = 'AetherTune_Acceptance_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const source = '1111111111111111111111111111111111111111';
  const support =
      '/Users/runner/Library/Developer/CoreSimulator/Devices/$device/'
      'data/Containers/Data/Application/AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE/'
      'Library/Application Support';
  Map<String, Object?> control(String phase) => {
    'device': device,
    'fixtureName': fixtureName,
    'sourceCommit': source,
    'phase': phase,
  };

  String validate({
    Map<String, Object?>? data,
    String? path,
    String compiledDevice = device,
    String compiledName = fixtureName,
    String compiledSource = source,
  }) => iosAcceptancePhase(
    controlJson: jsonEncode(data ?? control('seed')),
    supportPath: path ?? support,
    device: compiledDevice,
    fixtureName: compiledName,
    source: compiledSource,
  );

  test('reads all phases without an OS environment map', () {
    for (final phase in ['seed', 'reopen', 'sync']) {
      expect(validate(data: control(phase)), phase);
    }
  });

  test('rejects physical, other-guest and traversed app containers', () {
    for (final path in [
      '/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE/Library/Application Support',
      support.replaceFirst(device, 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE'),
      '$support/../Application Support',
      support.replaceFirst('CoreSimulator', 'NotCoreSimulator'),
      support.replaceFirst('Library/Application Support', 'Documents'),
      support.replaceFirst(
        'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',
        'arbitrary-directory',
      ),
    ]) {
      expect(() => validate(path: path), throwsFormatException, reason: path);
    }
  });

  test('rejects missing or malformed compiled identities', () {
    for (final value in [
      '',
      'booted',
      'all',
      '.*',
      device.replaceAll('-', ''),
    ]) {
      expect(() => validate(compiledDevice: value), throwsFormatException);
    }
    expect(
      () => validate(compiledName: 'Personal iPhone'),
      throwsFormatException,
    );
    expect(() => validate(compiledSource: 'main'), throwsFormatException);
  });

  test('rejects stale, mismatched or incomplete host control receipts', () {
    for (final field in ['device', 'fixtureName', 'sourceCommit', 'phase']) {
      expect(
        () => validate(data: {...control('seed'), field: 'wrong'}),
        throwsFormatException,
      );
      expect(
        () => validate(data: control('seed')..remove(field)),
        throwsFormatException,
      );
    }
    expect(() => validate(data: control('unknown')), throwsFormatException);
  });

  test('rejects malformed JSON and non-object control data', () {
    for (final value in ['{', 'null', '[]', 'true']) {
      expect(
        () => iosAcceptancePhase(
          controlJson: value,
          supportPath: support,
          device: device,
          fixtureName: fixtureName,
          source: source,
        ),
        throwsFormatException,
      );
    }
  });
}
