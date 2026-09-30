import 'dart:convert';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _putLibrarySync(String body) {
  return Request(
    'PUT',
    Uri.parse('http://localhost/api/v1/sync/library'),
    headers: {
      'authorization': 'Bearer test-token',
      'content-type': 'application/json',
    },
    body: body,
  );
}

Future<Map<String, Object?>> _readJsonError(Response response) async {
  expect(response.statusCode, 400);
  return jsonDecode(await response.readAsString()) as Map<String, Object?>;
}

void main() {
  final handler = createServerHandler(
    syncAuthenticator: StaticSyncAuthenticator({'primary': 'test-token'}),
    bodyReadTimeout: const Duration(seconds: 5),
  );

  test('rejects bodies nested beyond the JSON depth limit', () async {
    const depth = maxJsonNestingDepth + 1;
    final body = '${'{"a":' * depth}1${'}' * depth}';
    final response = await handler(_putLibrarySync(body));
    final error = await _readJsonError(response);
    expect(error['error'], 'invalid_sync_snapshot');
    expect(error['message'], 'Request JSON nesting is too deep.');
  });

  test('accepts nesting exactly at the JSON depth limit', () async {
    final padding = '[' * (maxJsonNestingDepth - 1);
    final body = '{"tracks":$padding${padding.replaceAll('[', ']')}}';
    final response = await handler(_putLibrarySync(body));
    final error = await _readJsonError(response);
    expect(error['message'], isNot('Request JSON nesting is too deep.'));
  });

  test('ignores structural characters inside JSON strings', () async {
    final braces = '{' * 100;
    final body = '{"tracks":"$braces"}';
    final response = await handler(_putLibrarySync(body));
    final error = await _readJsonError(response);
    expect(error['message'], isNot('Request JSON nesting is too deep.'));
  });

  test('handles escaped quotes before structural runs', () async {
    final braces = '{' * 100;
    final body = '{"tracks":"x\\"$braces"}';
    final response = await handler(_putLibrarySync(body));
    final error = await _readJsonError(response);
    expect(error['message'], isNot('Request JSON nesting is too deep.'));
  });

  test('server stays healthy after a deep-body rejection', () async {
    const depth = maxJsonNestingDepth + 5;
    final deep = '${'{"a":' * depth}1${'}' * depth}';
    final rejected = await handler(_putLibrarySync(deep));
    expect(rejected.statusCode, 400);

    final healthy = await handler(
      Request('GET', Uri.parse('http://localhost/api/v1/info')),
    );
    expect(healthy.statusCode, 200);
  });
}
