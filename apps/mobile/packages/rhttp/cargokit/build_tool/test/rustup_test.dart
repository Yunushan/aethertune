// Execute with Dart after resolving build_tool dependencies.
// Rustup commands use the existing fake-command override.
import 'dart:convert';
import 'dart:io';

import '../lib/src/rustup.dart';
import '../lib/src/util.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool same(List<String> a, List<String> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

Rustup fixture(
  String listing,
  Map<String, String> targets,
  List<List<String>> calls,
) {
  testRunCommandOverride = (args) {
    require(args.executable == 'rustup', 'Unexpected executable');
    calls.add(List.of(args.arguments));
    if (same(args.arguments, ['toolchain', 'list'])) {
      return TestRunCommandResult(stdout: listing);
    }
    if (args.arguments.length == 5 &&
        args.arguments[0] == 'target' &&
        args.arguments[1] == 'list' &&
        args.arguments[2] == '--toolchain' &&
        args.arguments[4] == '--installed' &&
        targets.containsKey(args.arguments[3])) {
      return TestRunCommandResult(stdout: targets[args.arguments[3]]!);
    }
    throw StateError('Unexpected Rustup command: ${args.arguments}');
  };
  return Rustup();
}

void main() {
  final results = <Map<String, Object?>>[];
  void run(String name, void Function() body) {
    try {
      body();
      results.add({'name': name, 'passed': true});
    } catch (error, stack) {
      results.add({
        'name': name,
        'passed': false,
        'error': error.toString(),
        'stack': stack.toString(),
      });
    } finally {
      testRunCommandOverride =
          (_) => throw StateError('No command is authorized between cases');
    }
  }

  run('numbered-pinned-target-cache', () {
    final calls = <List<String>>[];
    final name = '1.95.0-x86_64-pc-windows-msvc';
    final rustup = fixture(
      '$name (default)\r\n',
      {name: 'aarch64-linux-android\r\n'},
      calls,
    );
    final targets = rustup.installedTargets('1.95.0');
    require(targets != null, 'Numbered toolchain missing from cache');
    final cachedTargets = targets!;
    require(
      same(cachedTargets, ['aarch64-linux-android']),
      'Numbered target cache was not retained',
    );
    require(
      calls.length == 2 &&
          same(calls[0], ['toolchain', 'list']) &&
          same(calls[1], [
            'target',
            'list',
            '--toolchain',
            name,
            '--installed',
          ]),
      'Must only list toolchains and query the exact installed name',
    );
    var immutable = false;
    try {
      cachedTargets.add('other');
    } on UnsupportedError {
      immutable = true;
    }
    require(immutable, 'Target cache public view must remain immutable');
  });
  run('bare-numbered-default-and-minor-release-crlf', () {
    final calls = <List<String>>[];
    final rustup = fixture(
      '1.95.0 (default)\r\n1.94-x86_64-unknown-linux-gnu\n',
      {
        '1.95.0': 'x86_64-pc-windows-msvc\r\n',
        '1.94-x86_64-unknown-linux-gnu': 'x86_64-unknown-linux-gnu\n',
      },
      calls,
    );
    require(
      same(rustup.installedTargets('1.95.0')!, ['x86_64-pc-windows-msvc']),
      'Default annotation or CRLF polluted bare name or target',
    );
    require(
      same(rustup.installedTargets('1.94')!, ['x86_64-unknown-linux-gnu']),
      'Minor numbered release missing',
    );
    require(calls.length == 3, 'Unexpected extra query');
  });
  run('named-channel-date-host-and-default-preserved', () {
    final calls = <List<String>>[];
    final names = [
      'stable-x86_64-pc-windows-msvc',
      'beta-aarch64-apple-darwin',
      'nightly-2026-09-30-x86_64-unknown-linux-gnu',
    ];
    final rustup = fixture(
      '${names[0]} (default)\n${names[1]}\n${names[2]}\n',
      {for (final n in names) n: 'aarch64-linux-android\n'},
      calls,
    );
    for (final n in ['stable', 'beta', 'nightly-2026-09-30']) {
      require(
        same(rustup.installedTargets(n)!, ['aarch64-linux-android']),
        '$n missing',
      );
    }
    require(calls.length == 4, 'Changed named-channel query behavior');
  });
  run('custom-and-malformed-number-prefixes-excluded', () {
    final calls = <List<String>>[];
    final rustup = fixture(
      'my-toolchain\ncustom-1.95.0\n1.95.0junk\n1.95.000\n11.95.0\nnone\n',
      {},
      calls,
    );
    for (final n in [
      'my-toolchain',
      'custom-1.95.0',
      '1.95.0junk',
      '1.95.000',
      '11.95.0',
      'none',
    ]) {
      require(
        rustup.installedTargets(n) == null,
        '$n was queried as an official toolchain',
      );
    }
    require(calls.length == 1, 'Custom toolchains must not trigger target queries');
  });
  run('toolchain-list-query-error-propagates', () {
    final failure = CommandFailedException(
      executable: 'rustup',
      arguments: ['toolchain', 'list'],
      result: ProcessResult(1, 42, '', 'fake query failure'),
    );
    testRunCommandOverride = (_) => throw failure;
    Object? caught;
    try {
      Rustup();
    } catch (error) {
      caught = error;
    }
    require(
      identical(caught, failure),
      'List query exception was replaced or swallowed',
    );
  });
  run('target-list-query-error-propagates', () {
    final failure = CommandFailedException(
      executable: 'rustup',
      arguments: [
        'target',
        'list',
        '--toolchain',
        'stable-x86_64-pc-windows-msvc',
        '--installed',
      ],
      result: ProcessResult(1, 43, '', 'fake target failure'),
    );
    testRunCommandOverride = (args) {
      if (same(args.arguments, ['toolchain', 'list'])) {
        return TestRunCommandResult(stdout: 'stable-x86_64-pc-windows-msvc\n');
      }
      throw failure;
    };
    Object? caught;
    try {
      Rustup();
    } catch (error) {
      caught = error;
    }
    require(
      identical(caught, failure),
      'Target query exception was replaced or swallowed',
    );
  });
  testRunCommandOverride = (_) => throw StateError('Rustup execution prohibited');
  print(jsonEncode({
    'checks': results,
    'passed': results.where((r) => r['passed'] == true).length,
    'total': results.length,
    'skipped': 0,
    'fakeCommandsOnly': true,
  }));
  if (results.any((r) => r['passed'] != true)) exitCode = 1;
}
