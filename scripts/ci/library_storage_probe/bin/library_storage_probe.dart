import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../../../apps/mobile/lib/src/data/file_library_storage.dart';

// A line protocol keeps process control in the acceptance driver. No storage
// behavior is mocked: each command calls the same backend used by the app.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Expected a disposable library directory.');
    exitCode = 64;
    return;
  }
  final directory = Directory(arguments.single);
  final input = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  Future<void> emit(Map<String, Object?> value) async {
    stdout.writeln(jsonEncode({...value, 'max_rss_bytes': ProcessInfo.maxRss}));
    await stdout.flush();
  }

  Future<void> waitForContinue(File pending) async {
    await emit({'event': 'pending_flushed', 'bytes': await pending.length()});
    if (!await input.moveNext() || input.current != 'continue') {
      throw const FormatException('Paused writer did not receive continue.');
    }
  }

  await emit({'event': 'ready', 'pid': pid});
  try {
    while (await input.moveNext()) {
      try {
        final command = jsonDecode(input.current) as Map<String, dynamic>;
        final storage = FileLibraryStorage(
          directory: () async => directory,
          beforeCommit: command['pause'] == true ? waitForContinue : null,
        );
        await emit({'event': 'started', 'operation': command['operation']});
        switch (command['operation']) {
          case 'read':
            final saved = await storage.read();
            await emit({
              'event': 'read',
              'revision': saved?.revision,
              'values': saved?.values,
            });
          case 'write':
            final saved = await storage.write(
              Map<String, Object?>.from(command['values'] as Map),
              expectedRevision: command['revision'] as String?,
            );
            await emit({'event': 'committed', 'revision': saved.revision});
          case 'recover_previous':
            await storage.recoverPrevious();
            await emit({'event': 'recovered'});
          default:
            throw const FormatException('Unsupported probe operation.');
        }
      } on LibraryStorageConflict {
        await emit({'event': 'conflict'});
      } on SqliteException catch (error) {
        await emit({
          'event': 'sqlite_error',
          'code': error.resultCode,
          'extended_code': error.extendedResultCode,
          'message': error.message,
          'operation': error.operation,
        });
      } on FileSystemException catch (error) {
        await emit({
          'event': 'filesystem_error',
          'code': error.osError?.errorCode,
          'message': error.osError?.message,
        });
      } catch (error) {
        await emit({'event': 'error', 'type': error.runtimeType.toString()});
      }
    }
  } finally {
    await input.cancel();
  }
}
