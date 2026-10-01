import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';

void main() {
  late Directory directory;
  late String runtimePath;
  final cliPath = File('bin/marionette_agent.dart').absolute.path;
  Future<ProcessResult> cli(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    [cliPath, '--session', 'issue13', ...args],
    environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtimePath},
  );
  setUp(() async {
    directory = await Directory('/tmp').createTemp('mra-jpeg-');
    runtimePath = '${directory.path}/runtime';
  });
  tearDown(() => directory.delete(recursive: true));

  test('product CLI passes format/quality to local saving and renders text/JSON paths', () async {
    final fixture = image.Image(width: 9, height: 7);
    for (final pixel in fixture) {
      pixel.setRgb(pixel.x * 29, pixel.y * 37, 128);
    }
    final png = image.encodePng(fixture);
    final backend = FakeBackend()..screenshots = [base64Encode(png)];
    final runtime = await RuntimeDirectory.prepare(directory: runtimePath);
    final server = DaemonServer(
      runtime,
      SessionManager(() => backend, coreCommands()),
    );
    final serving = server.run();
    try {
      while (!File(runtime.metadata).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect((await cli(['connect', 'http://localhost:1/'])).exitCode, 0);
      final pngPath = '${directory.path}/default.png';
      final savedPng = await cli(['screenshot', pngPath]);
      expect(savedPng.exitCode, 0);
      expect(jsonDecode(savedPng.stdout as String), {
        'paths': [pngPath],
      });
      expect(savedPng.stderr, isEmpty);
      expect(await File(pngPath).readAsBytes(), png);

      for (final quality in [null, 0, 100]) {
        final path = '${directory.path}/q${quality ?? 'default'}.jpg';
        final result = await cli([
          '--screenshot-format=jpeg',
          'screenshot',
          path,
          '--json',
          if (quality != null) '--screenshot-quality=$quality',
        ]);
        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
        final response = jsonDecode(result.stdout as String) as Map;
        expect(response['ok'], isTrue);
        expect(response['session'], 'issue13');
        expect(response['data'], {
          'paths': [path],
        });
        final bytes = await File(path).readAsBytes();
        expect(bytes, image.encodeJpg(fixture, quality: quality ?? 90));
        expect(image.decodeJpg(bytes)!.width, 9);
      }
      expect(
        backend.calls.where((c) => c == 'captureScreenshots'),
        hasLength(4),
      );
      expect((await cli(['close'])).exitCode, 0);
      await serving;
      expect(File(runtime.metadata).existsSync(), isFalse);
    } finally {
      await server.close();
      await serving;
    }
  });

  test(
    'invalid screenshot options fail in text/JSON before runtime or connection',
    () async {
      for (final args in [
        ['screenshot', 'image.jpg', '--json'],
        ['screenshot', '--screenshot-quality=90'],
        [
          'screenshot',
          '--screenshot-format=jpeg',
          '--screenshot-quality=101',
          '--json',
        ],
      ]) {
        final result = await cli(args);
        expect(result.exitCode, 2);
        expect(result.stderr, isEmpty);
        if (args.contains('--json')) {
          final response = jsonDecode(result.stdout as String) as Map;
          expect(response['session'], 'issue13');
          expect(response['error']['code'], 'INVALID_ARGUMENT');
          expect(response['error']['outcome'], 'not_sent');
        } else {
          expect(result.stdout, contains('INVALID_ARGUMENT'));
          expect(result.stdout, contains('Outcome: not_sent'));
          expect(result.stdout, contains('--screenshot-quality'));
        }
        expect(Directory(runtimePath).existsSync(), isFalse);
        expect(directory.listSync(), isEmpty);
      }
    },
  );
}
