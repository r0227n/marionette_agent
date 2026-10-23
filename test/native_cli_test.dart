import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/platform/native/native_service.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/native_backend.dart';

void main() {
  test(
    'product CLI crosses IPC without VM, limits refs and saves native PNG/JPEG',
    () async {
      final dir = await Directory('/tmp').createTemp('native-cli-');
      final runtime = await RuntimeDirectory.prepare(
        directory: '${dir.path}/runtime',
      );
      final backend = FakeNativeBackend()
        ..png = image.encodePng(image.Image(width: 12, height: 20));
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
        final snap = await cli([
          'native',
          'snapshot',
          ...device,
          '--content-boundaries',
        ]);
        expect(snap.exitCode, 0, reason: '${snap.stdout} ${snap.stderr}');
        final data = (jsonDecode(snap.stdout as String) as Map)['data'];
        expect(data['source'], 'native');
        expect(data['contentBoundary']['source'], 'snapshot');
        final ref = data['elements'][0]['ref'] as String;
        final tap = await cli(['native', 'tap', ...device, ref]);
        expect(tap.exitCode, 0);
        expect(backend.taps, [(60.0, 40.0)]);
        expect((await cli(['native', 'tap', ...device, ref])).exitCode, 4);
        final path = '${dir.path}/native.png';
        final shot = await cli(['native', 'screenshot', ...device, path]);
        expect(shot.exitCode, 0);
        expect(
          (jsonDecode(shot.stdout as String) as Map)['data']['source'],
          'native',
        );
        expect(await File(path).readAsBytes(), backend.png);
        expect(
          (await cli(['native', 'screenshot', ...device, path])).exitCode,
          1,
        );
        final jpeg = '${dir.path}/native.jpg';
        expect(
          (await cli([
            'native',
            'screenshot',
            ...device,
            jpeg,
            '--screenshot-format=jpeg',
          ])).exitCode,
          0,
        );
        expect(image.decodeJpg(await File(jpeg).readAsBytes())!.height, 20);
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
