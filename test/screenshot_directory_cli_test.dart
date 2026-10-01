import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_backend.dart';

void main() {
  test('product CLI saves text/JSON paths in its cwd and keeps directory options local', () async {
    final temporaryRoot = await Directory('/tmp').createTemp('mra-shot-');
    // A child process resolves macOS /tmp to /private/tmp as its actual cwd.
    final root = Directory(await temporaryRoot.resolveSymbolicLinks());
    final runtime = await RuntimeDirectory.prepare(
      directory: p.join(root.path, 'runtime'),
    );
    final bytes = image.encodePng(image.Image(width: 2, height: 2));
    final backend = FakeBackend()..screenshots = [base64Encode(bytes)];
    final manager = SessionManager(() => backend, coreCommands());
    final server = DaemonServer(runtime, manager);
    final serving = server.run();
    final cliPath = File('bin/marionette_agent.dart').absolute.path;
    final output = await Directory(p.join(root.path, 'images')).create();
    Future<ProcessResult> cli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      [cliPath, '--session', 'screenshots', ...args],
      workingDirectory: root.path,
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    Json data(ProcessResult result, {bool json = true}) {
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, '');
      final body = asJson(jsonDecode(result.stdout as String));
      if (!json) return body;
      expect(body['ok'], isTrue);
      expect(body['session'], 'screenshots');
      return asJson(body['data']);
    }

    try {
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return !File(runtime.metadata).existsSync();
      }).timeout(const Duration(seconds: 5));
      final connected = await manager.handle(
        Request(
          requestId: 'setup',
          session: 'screenshots',
          command: 'connect',
          params: {'uri': 'http://localhost:1/'},
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      expect(connected.exitCode, 0);
      final saved = <String>[];
      for (final json in [false, true]) {
        final result = data(
          await cli([
            if (!json) ...['--screenshot-dir', 'images'],
            'screenshot',
            if (json) ...['--screenshot-dir=images', '--json'],
          ]),
          json: json,
        );
        final path = (result['paths'] as List).single as String;
        expect(p.dirname(path), output.path);
        expect(await File(path).readAsBytes(), bytes);
        saved.add(path);
      }
      expect(saved.toSet(), hasLength(2));
      final explicit = data(
        await cli([
          'screenshot',
          'explicit.png',
          '--screenshot-dir=missing',
          '--json',
        ]),
      );
      expect(explicit['paths'], [p.join(root.path, 'explicit.png')]);
      expect(
        await File(p.join(root.path, 'explicit.png')).readAsBytes(),
        bytes,
      );
      expect(Directory(p.join(root.path, 'missing')).existsSync(), isFalse);
      final temporary = data(await cli(['screenshot', '--json']));
      final temporaryFile = File((temporary['paths'] as List).single as String);
      try {
        expect(p.isAbsolute(temporaryFile.path), isTrue);
        expect(p.isWithin(root.path, temporaryFile.path), isFalse);
        expect(p.basename(temporaryFile.path), 'screen.png');
        expect(await temporaryFile.readAsBytes(), bytes);
      } finally {
        await temporaryFile.parent.delete(recursive: true);
      }
      final failure = await cli([
        'screenshot',
        '--screenshot-dir=missing',
        '--json',
      ]);
      expect(failure.exitCode, 1);
      expect(failure.stderr, '');
      final error = asJson(jsonDecode(failure.stdout as String));
      expect(error['ok'], isFalse);
      expect(error['session'], 'screenshots');
      expect(asJson(error['error'])['code'], 'IO_ERROR');
      expect(asJson(error['error'])['outcome'], 'not_sent');
      expect(output.listSync(), hasLength(2));
    } finally {
      await server.close();
      await serving;
      await root.delete(recursive: true);
    }
  });
}
