import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/artifacts/artifact_writer.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/mcp/catalog.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/workflow/model.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';
import 'workflow_model_test.dart' show doc;

void main() {
  late Directory root;
  late FakeBackend backend;
  late SessionManager manager;
  late Json native;
  late List<int> displays;
  AgentError? failure;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-screenshot-test-');
    backend = FakeBackend();
    displays = [];
    failure = null;
    native = {
      'images': [
        base64Encode(image.encodePng(image.Image(width: 4, height: 2))),
      ],
      'capture': {
        'source': 'macos-screencapture',
        'scope': 'display',
        'displayIndex': 2,
        'displayId': 52,
        'pixelWidth': 4,
        'pixelHeight': 2,
        'includesOtherApplications': true,
      },
    };
    manager = SessionManager(
      () => backend,
      coreCommands(
        captureNative: (display, deadline) async {
          displays.add(display);
          if (failure != null) throw failure!;
          return native;
        },
      ),
    );
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
  });
  tearDown(() async {
    await manager.dispose();
    await root.delete(recursive: true);
  });
  test(
    'CLI defaults preserve Flutter and native source requires explicit display',
    () {
      final parser = CliParser();
      expect(parser.parse(['screenshot']).params, isEmpty);
      expect(
        parser.parse(['screenshot', '--source=macos', '--display=2']).params,
        {'source': 'macos', 'display': 2},
      );
      for (final args in [
        ['--source=macos'],
        ['--display=1'],
        ['--source=macos', '--display=0'],
        ['--source=macos', '--display=01'],
        ['--source=macos', '--display=2', '--annotate'],
        ['--source=macos', '--display=2', '--key=button'],
        ['--source=macos', '--display=2', '@e1'],
      ]) {
        expect(
          () => parser.parse(['screenshot', ...args]),
          throwsA(isA<AgentError>()),
          reason: '$args',
        );
      }
    },
  );
  test('MCP passes typed native selection through the product CLI parser', () {
    final tool = mcpToolCatalog().singleWhere(
      (tool) => tool.name == 'screenshot',
    );
    final args = tool.arguments({
      'source': 'macos',
      'display': 2,
      'path': 'native.png',
    }, const CommonOptions());
    expect(CliParser().parse(args).params, {
      'source': 'macos',
      'display': 2,
      'path': 'native.png',
    });
  });
  test(
    'native dispatch bypasses Flutter capture and errors never fall back',
    () async {
      final params = {'source': 'macos', 'display': 2};
      final shot = await manager.handle(request('screenshot', params: params));
      expect(shot.error, isNull);
      expect(shot.data, native);
      failure = const AgentError(
        'SCREEN_CAPTURE_PERMISSION_REQUIRED',
        'not granted',
      );
      final rejected = await manager.handle(
        request('screenshot', params: params),
      );
      expect(rejected.error!.code, 'SCREEN_CAPTURE_PERMISSION_REQUIRED');
      expect(rejected.error!.outcome, Outcome.notSent);
      expect(backend.calls, ['connect']);
      expect(displays, [2, 2]);
    },
  );
  test(
    'shared PNG/JPEG writer retains native dimensions and exclusive paths',
    () async {
      for (final format in ScreenshotFormat.values) {
        final file = '${root.path}/shot${format.extension}';
        final saved = await saveScreenshots(
          native,
          file,
          DateTime.now().add(const Duration(seconds: 5)),
          format: format,
        );
        expect(saved['capture'], native['capture']);
        final decoded = image.decodeImage(await File(file).readAsBytes())!;
        expect([decoded.width, decoded.height], [4, 2]);
        await expectLater(
          saveScreenshots(
            native,
            file,
            DateTime.now().add(const Duration(seconds: 5)),
            format: format,
          ),
          throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
        );
      }
    },
  );
  test('metadata mismatch rejects saving without an output file', () async {
    (native['capture'] as Map)['pixelWidth'] = 5;
    await expectLater(
      saveScreenshots(
        native,
        '${root.path}/wrong.png',
        DateTime.now().add(const Duration(seconds: 5)),
      ),
      throwsA(isA<AgentError>()),
    );
    expect(root.listSync(), isEmpty);
  });
  test(
    'workflow saves before next action, keeps previous files on later failure',
    () async {
      final file = '${root.path}/step.jpg';
      final flow = doc([
        {
          'id': 'proof',
          'action': 'screenshot',
          'source': 'macos',
          'display': 2,
          'path': file,
        },
        {
          'id': 'again',
          'action': 'screenshot',
          'source': 'macos',
          'display': 2,
          'path': file,
        },
        {'id': 'never', 'action': 'snapshot'},
      ]);
      expect(WorkflowPlan.decode(flow).steps.length, 3);
      final result = await manager.handle(
        request(
          'workflow',
          params: {
            'workflow': flow,
            'inputs': <String, Object?>{},
            'screenshotOptions': {'format': 'jpeg', 'quality': 80},
          },
        ),
      );
      expect(result.error!.code, 'IO_ERROR');
      expect(result.error!.details!['completedSteps'], 1);
      expect(result.error!.details!['stepId'], 'again');
      expect((result.error!.details!['screenshots'] as List).single['paths'], [
        file,
      ]);
      expect(image.decodeJpg(await File(file).readAsBytes()), isNotNull);
      expect(backend.calls, ['connect']);
    },
  );
  test(
    'workflow invalid native options are rejected before any capture',
    () async {
      final result = await manager.handle(
        request(
          'workflow',
          params: {
            'workflow': doc([
              {
                'id': 'proof',
                'action': 'screenshot',
                'source': 'macos',
                'display': 2,
              },
              {
                'id': 'bad',
                'action': 'screenshot',
                'source': 'macos',
                'display': 2,
                'annotate': true,
              },
            ]),
            'inputs': <String, Object?>{},
          },
        ),
      );
      expect(result.error!.code, 'INVALID_ARGUMENT');
      expect(displays, isEmpty);
    },
  );
}
