import 'dart:async';
import 'dart:io';

import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

/// Separate close response completion from cleanup completion to reproduce shutdown contention reliably.
class _DelayedDispose extends SessionManager {
  _DelayedDispose() : super(FakeBackend.new, coreCommands());
  final entered = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<void> dispose() async {
    entered.complete();
    await proceed.future;
    await super.dispose();
  }
}

void main() {
  test(
    'shutdown waits for cleanup after delivering the final response',
    () async {
      final directory = await Directory('/tmp').createTemp('mra-shutdown-');
      await Process.run('chmod', ['700', directory.path]);
      final runtime = await RuntimeDirectory.prepare(directory: directory.path);
      final manager = _DelayedDispose();
      final server = DaemonServer(runtime, manager);
      var exited = false;
      final running = server.run().then((_) {
        exited = true;
      });
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!File(runtime.metadata).existsSync()) {
          if (DateTime.now().isAfter(deadline)) fail('Daemon did not start');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final client = DaemonClient(runtime);
        expect(
          (await client.send(
            request('connect', params: {'uri': 'http://localhost:1/'}),
          )).exitCode,
          0,
        );
        final response = client.send(request('close'));
        await manager.entered.future;
        expect((await response).exitCode, 0);
        var cleanupFinished = false;
        final cleanup = server.close().then((_) {
          cleanupFinished = true;
        });
        // Even after sending a response, keep run and repeated close waiting while dispose is unfinished.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cleanupFinished, isFalse);
        expect(exited, isFalse);
        manager.proceed.complete();
        await Future.wait([cleanup, running]);
        expect(File(runtime.metadata).existsSync(), isFalse);
        expect(
          FileSystemEntity.typeSync(runtime.socket),
          FileSystemEntityType.notFound,
        );
      } finally {
        if (!manager.proceed.isCompleted) manager.proceed.complete();
        await server.close();
        await running;
        await directory.delete(recursive: true);
      }
    },
  );
}
