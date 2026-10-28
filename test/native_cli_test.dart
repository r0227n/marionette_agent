import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/platform/native/native_service.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/native_backend.dart';

void main() {
  test('session bind starts a cold daemon without a Flutter VM', () async {
    final dir = await Directory('/tmp').createTemp('native-bind-');
    final runtime = '${dir.path}/runtime';
    Future<ProcessResult> cli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      [File('bin/marionette_agent.dart').absolute.path, '--json', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime},
    );
    try {
      final result = await cli([
        'session',
        'bind',
        '--platform=android',
        '--device=emulator-5554',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
      final shown = jsonDecode(
        (await cli(['session', 'show'])).stdout as String,
      );
      expect(shown['data']['nativeTarget'], 'android:emulator-5554');
      expect(shown['data']['state'], 'disconnected');
    } finally {
      await cli(['close']);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (File('$runtime/daemon.json').existsSync() &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(File('$runtime/daemon.json').existsSync(), isFalse);
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'product CLI crosses IPC without VM and invalidates refs after input',
    () async {
      final dir = await Directory('/tmp').createTemp('native-cli-');
      final runtime = await RuntimeDirectory.prepare(
        directory: '${dir.path}/runtime',
      );
      final backend = FakeNativeBackend();
      final server = DaemonServer(
        runtime,
        SessionManager(
          FakeBackend.new,
          coreCommands(),
          native: NativeService(backends: {'android': backend}),
        ),
      );
      final serving = server.run();
      Future<ProcessResult> cli(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        [
          File('bin/marionette_agent.dart').absolute.path,
          '--session=native-cli',
          '--json',
          ...args,
        ],
        environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
      );
      const device = ['--platform=android', '--device=emulator-5554'];
      try {
        while (!File(runtime.metadata).existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect((await cli(['session', 'bind', ...device])).exitCode, 0);
        final snap = await cli(['snapshot', '--content-boundaries']);
        expect(snap.exitCode, 0, reason: '${snap.stdout} ${snap.stderr}');
        final data = (jsonDecode(snap.stdout as String) as Map)['data'];
        expect(data['source'], 'native');
        expect(data['contentBoundary']['source'], 'snapshot');
        final ref = data['elements'][0]['ref'] as String;
        final tap = await cli(['tap', ref]);
        expect(tap.exitCode, 0);
        expect(backend.taps, [(60.0, 40.0)]);
        expect((await cli(['tap', ref])).exitCode, 4);
        expect(
          (await cli(['native', 'screenshot', ...device])).exitCode,
          isNot(0),
        );
        expect((await cli(['close'])).exitCode, 0);
        await serving;
      } finally {
        await server.close();
        await serving;
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
