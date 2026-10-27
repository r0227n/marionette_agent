import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/workflow_screenshots.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/mcp/catalog.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

class Capturer implements ScreenCapturer {
  Uint8List png = image.encodePng(image.Image(width: 7, height: 13));
  int calls = 0;
  PlatformException? error;
  @override
  Future<CapturedScreen> capture(String device, DateTime deadline) async {
    calls++;
    if (error != null) throw error!;
    return CapturedScreen(
      png,
      source: 'android-uiautomator',
      device: device,
      display: 0,
    );
  }
}

void main() {
  late Directory directory;
  late Capturer capturer;
  late FakeBackend backend;
  late SessionManager manager;
  const params = {'platform': 'android', 'device': 'emulator-5660'};
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 10));
  setUp(() async {
    directory = await Directory('/tmp').createTemp('native-shot-');
    capturer = Capturer();
    backend = FakeBackend();
    manager = SessionManager(() => backend, coreCommands(capturer: capturer));
  });
  tearDown(() async {
    await manager.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'CLI and MCP share explicit platform/device, rejecting mixed coordinates',
    () {
      final parser = CliParser(environment: {});
      final tool = mcpToolCatalog().singleWhere(
        (tool) => tool.name == 'screenshot',
      );
      final invocation = parser.parse(
        tool.arguments({...params, 'display': '0'}, const CommonOptions()),
      );
      expect(invocation.params, {
        ...params,
        'device': File(params['device'] as String).absolute.path,
        'display': '0',
      });
      for (final args in [
        ['--platform=android'],
        ['--platform=android', '--device=emulator-5660', '--annotate'],
        ['--platform=android', '--device=emulator-5660', '--key=button'],
        ['--platform=flutter', '--device=emulator-5660'],
        ['--platform=android', '--device=emulator-5660', '--display=1'],
      ]) {
        expect(
          () => parser.parse(['screenshot', ...args]),
          throwsA(isA<AgentError>()),
        );
      }
    },
  );

  test('standalone native screenshot needs no backend connection', () async {
    final result = await manager.handle(request('screenshot', params: params));
    expect(result.error, isNull);
    expect(capturer.calls, 1);
    expect(backend.calls, isEmpty);
    final saved = await saveScreenshots(
      result.data!,
      '${directory.path}/screen.jpg',
      deadline(),
      format: ScreenshotFormat.jpeg,
    );
    expect((saved['capture'] as Map)['width'], 7);
    expect((saved['capture'] as Map)['height'], 13);
    expect((saved['capture'] as Map)['coordinateSpace'], 'physical-pixels');
    expect(
      image
          .decodeJpg(
            await File((saved['paths'] as List).single as String).readAsBytes(),
          )!
          .height,
      13,
    );
  });

  test(
    'capture failure never calls Flutter fallback or writes a successful path',
    () async {
      await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      capturer.error = const PlatformException('IO_ERROR', 'capture denied');
      final result = await manager.handle(
        request('screenshot', params: params),
      );
      expect(result.error!.code, 'IO_ERROR');
      expect(capturer.calls, 1);
      expect(backend.calls, isNot(contains('captureScreen')));
      expect(directory.listSync(), isEmpty);
    },
  );

  test(
    'corrupt bytes fail decoding with no files; existing outputs remain intact',
    () async {
      capturer.png = Uint8List.fromList([1, 2, 3]);
      final result = await manager.handle(
        request('screenshot', params: params),
      );
      await expectLater(
        saveScreenshots(result.data!, '${directory.path}/bad.png', deadline()),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR'),
        ),
      );
      expect(directory.listSync(), isEmpty);
      final file = File('${directory.path}/keep.png')
        ..writeAsStringSync('keep');
      final good = {
        'images': [base64Encode(Capturer().png)],
      };
      await expectLater(
        saveScreenshots(good, file.path, deadline()),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
      expect(file.readAsStringSync(), 'keep');
    },
  );

  test('workflow shares capture service, retains refs and saves atomically on caller', () async {
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
    final result = await manager.handle(
      request(
        'workflow',
        params: {
          'inputs': <String, Object?>{},
          'workflow': {
            'schemaVersion': 1,
            'name': 'native',
            'steps': [
              {'id': 'observe', 'action': 'snapshot'},
              {
                'id': 'capture',
                'action': 'screenshot',
                ...params,
                'path': '${directory.path}/workflow.png',
              },
            ],
          },
        },
      ),
    );
    expect(result.error, isNull);
    expect(result.data!['requiresSnapshot'], false);
    expect(capturer.calls, 1);
    expect(backend.calls, isNot(contains('captureScreen')));
    final saved = await saveWorkflowScreenshots(
      result.data!,
      const CommonOptions(),
      deadline(),
    );
    expect((saved['screenshots'] as List).single['stepId'], 'capture');
    expect(File('${directory.path}/workflow.png').existsSync(), true);
    final raw = (result.data!['screenshots'] as List).single as Map;
    await expectLater(
      saveWorkflowScreenshots(
        {
          'screenshots': [
            {...raw, 'path': '${directory.path}/rollback.png'},
            {...raw, 'path': '${directory.path}/workflow.png'},
          ],
        },
        const CommonOptions(),
        deadline(),
      ),
      throwsA(isA<AgentError>()),
    );
    expect(File('${directory.path}/rollback.png').existsSync(), false);
  });

  test('product CLI persists native metadata in text and JSON', () async {
    // Keep an unrelated connected session alive while native-only requests finish.
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
    final runtime = await RuntimeDirectory.prepare(
      directory: '${directory.path}/runtime',
    );
    final server = DaemonServer(runtime, manager);
    final serving = server.run();
    try {
      while (!File(runtime.metadata).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (final json in [false, true]) {
        final path = '${directory.path}/$json.png';
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            File('bin/marionette_agent.dart').absolute.path,
            if (json) '--json',
            'screenshot',
            '--platform=android',
            '--device=emulator-5660',
            path,
          ],
          environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
        );
        expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
        expect(result.stderr, isEmpty);
        final decoded = jsonDecode(result.stdout as String) as Map;
        final data = json ? decoded['data'] as Map : decoded;
        expect(data['paths'], [path]);
        expect(data['capture']['device'], File('emulator-5660').absolute.path);
        expect(data['capture']['width'], 7);
      }
    } finally {
      await server.close();
      await serving;
    }
  });
}
