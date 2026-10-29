import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/workflow_artifacts.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/workflow/model.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/fake_screen_capturer.dart';
import 'support/requests.dart';

final native = <String, Object?>{
  'source': 'ios-simulator',
  'device': screenshotDevice,
};
Json workflow(List<Json> steps) => {
  'workflow': {'schemaVersion': 1, 'name': 'native', 'steps': steps},
  'inputs': <String, Object?>{},
};
void main() {
  late FakeBackend backend;
  late FakeScreenCapturer capturer;
  late SessionManager manager;
  setUp(() {
    backend = FakeBackend()..screenshots = ['legacy'];
    capturer = FakeScreenCapturer(
      image.encodePng(image.Image(width: 9, height: 7)),
    );
    manager = SessionManager(
      () => backend,
      coreCommands(),
      screenCapturer: capturer,
    );
  });
  tearDown(() => manager.dispose());
  test('native screenshot succeeds without a Flutter connection', () async {
    final result = await manager.handle(request('screenshot', params: native));
    expect(result.error, isNull);
    expect(result.data!['capture'], containsPair('device', screenshotDevice));
    expect(backend.calls, isEmpty);
    expect(capturer.devices, [screenshotDevice]);
  });
  test(
    'native failure never falls back and implicit Flutter capture is removed',
    () async {
      await manager.handle(
        request('connect', params: {'uri': 'ws://localhost:1/ws'}),
      );
      capturer.failure = const PlatformException('IO_ERROR', 'Capture failed');
      final result = await manager.handle(
        request('screenshot', params: native),
      );
      expect(result.error!.code, 'IO_ERROR');
      expect(result.error!.outcome, Outcome.notSent);
      expect(backend.calls, isNot(contains('captureScreenshots')));
      final legacy = await manager.handle(request('screenshot'));
      expect(legacy.error!.code, 'INVALID_ARGUMENT');
    },
  );
  test(
    'physical device and native annotation/crop are explicit errors',
    () async {
      for (final params in [
        {'source': 'ios-device', 'device': '00008110-0000000000000000'},
        {...native, 'annotate': true},
        {...native, 'ref': '@e1'},
        {...native, 'key': 'input'},
      ]) {
        final m = SessionManager(
          () => backend,
          coreCommands(),
          screenCapturer: capturer,
        );
        final result = await m.handle(request('screenshot', params: params));
        expect(result.error!.code, 'UNSUPPORTED_CAPABILITY');
        await m.dispose();
      }
      expect(capturer.devices, isEmpty);
      expect(backend.calls, isEmpty);
    },
  );
  test('CLI requires a device, defaults to native and rejects removed Flutter capture', () {
    final parser = CliParser(environment: {});
    expect(parser.parse(['screenshot', '--device=$screenshotDevice']).params, {
      'device': screenshotDevice,
    });
    expect(
      parser.parse([
        'screenshot',
        '--source=ios-simulator',
        '--device=$screenshotDevice',
      ]).params,
      native,
    );
    for (final args in [
      ['--source=ios-simulator'],
      ['--source=ios-simulator', '--device=booted'],
      ['--source=flutter', '--device=$screenshotDevice'],
      ['--source=unknown'],
      [
        '--source=ios-simulator',
        '--device=$screenshotDevice',
        '--source=flutter',
      ],
    ]) {
      expect(
        () => parser.parse(['screenshot', ...args]),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
        ),
      );
    }
  });
  test('native-only workflow shares capture path without a backend', () async {
    final result = await manager.handle(
      request(
        'workflow',
        params: workflow([
          {'id': 'proof', 'action': 'screenshot', ...native},
        ]),
      ),
    );
    expect(result.error, isNull);
    expect(result.data!['completedSteps'], 1);
    expect((result.data!['screenshots'] as List).single['stepId'], 'proof');
    expect(capturer.devices, [screenshotDevice]);
    expect(backend.calls, isEmpty);
  });
  test('workflow validates all native targets before mutations', () {
    final params = workflow([
      {
        'id': 'tap',
        'action': 'tap',
        'target': {'key': 'button'},
      },
      {
        'id': 'shot',
        'action': 'screenshot',
        'source': 'ios-simulator',
        'device': 'booted',
      },
    ]);
    expect(
      () => WorkflowPlan.decode(params['workflow']),
      throwsA(isA<AgentError>()),
    );
  });
  test(
    'capture failure stops workflow with completed-step accounting',
    () async {
      capturer.failure = const PlatformException('TIMEOUT', 'capture expired');
      final result = await manager.handle(
        request(
          'workflow',
          params: workflow([
            {'id': 'first', 'action': 'screenshot', ...native},
            {'id': 'second', 'action': 'screenshot', ...native},
          ]),
        ),
      );
      expect(result.error!.code, 'TIMEOUT');
      expect(result.error!.details, containsPair('completedSteps', 0));
      expect(result.error!.details, containsPair('stepId', 'first'));
      expect(capturer.devices, hasLength(1));
      expect(backend.calls, isEmpty);
    },
  );
  group('shared artifact writer', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('native-save-');
    });
    tearDown(() => root.delete(recursive: true));
    Future<Json> payload() async => {
      'images': [base64Encode(capturer.png)],
      'capture': (await capturer.capture(
        screenshotDevice,
        DateTime.now(),
      )).metadata,
    };
    DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));
    test(
      'PNG/JPEG, caller directory, size/orientation and overwrite protection',
      () async {
        final data = await payload();
        final result = await saveScreenshots(
          data,
          null,
          deadline(),
          screenshotDir: root.path,
        );
        final path = (result['paths'] as List).single as String;
        expect(await File(path).readAsBytes(), capturer.png);
        expect(result['capture'], containsPair('pixelWidth', 9));
        expect(result['capture'], containsPair('pixelHeight', 7));
        expect(result['capture'], containsPair('orientation', 'landscape'));
        final jpeg = await saveScreenshots(
          data,
          '${root.path}/screen.jpg',
          deadline(),
          format: ScreenshotFormat.jpeg,
        );
        expect(jpeg['capture'], result['capture']);
        expect(
          image
              .decodeJpg(await File('${root.path}/screen.jpg').readAsBytes())!
              .width,
          9,
        );
        await expectLater(
          saveScreenshots(data, path, deadline()),
          throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
        );
        expect(await File(path).readAsBytes(), capturer.png);
      },
    );
    test(
      'JPEG retains XCUIScreen landscape EXIF without rotating raster pixels',
      () async {
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAGmVYSWZNTQAqAAAACAABARIAAwAAAAEABgAAAAAAANZnS2kAAAARSURBVHicY/jPwABEDGAShgA+1gX72hMcmAAAAABJRU5ErkJggg==',
        );
        final data = {
          'images': [base64Encode(png)],
        };
        final pngPath = '${root.path}/original.png';
        await saveScreenshots(data, pngPath, deadline());
        expect(await File(pngPath).readAsBytes(), png);
        final path = '${root.path}/landscape.jpg';
        await saveScreenshots(
          data,
          path,
          deadline(),
          format: ScreenshotFormat.jpeg,
        );
        final bytes = await File(path).readAsBytes();
        final raster = image.JpegDecoder().startDecode(bytes)!;
        expect([raster.width, raster.height], [2, 3]);
        // The JPEG decoder applies EXIF orientation, just like an image viewer.
        final displayed = image.decodeJpg(bytes)!;
        expect([displayed.width, displayed.height], [3, 2]);
      },
    );
    test('invalid native PNG and timeout leave no artifacts', () async {
      final data = await payload();
      await expectLater(
        saveScreenshots(
          {
            ...data,
            'images': ['broken'],
          },
          null,
          deadline(),
          screenshotDir: root.path,
        ),
        throwsA(isA<AgentError>()),
      );
      await expectLater(
        saveScreenshots(data, null, DateTime.now(), screenshotDir: root.path),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      expect(root.listSync(), isEmpty);
    });
    test('workflow save failure rolls back new files and preserves existing output', () async {
      final data = await payload();
      final existing = File('${root.path}/exists.png');
      await existing.writeAsString('keep');
      await expectLater(
        saveWorkflowScreenshots(
          {
            'workflow': 'proof',
            'completedSteps': 2,
            'screenshots': [
              {...data, 'stepId': 'one', 'path': '${root.path}/new.png'},
              {...data, 'stepId': 'two', 'path': existing.path},
            ],
          },
          const CommonOptions(),
          deadline(),
        ),
        throwsA(
          isA<AgentError>().having(
            (e) => e.details!['completedSteps'],
            'completedSteps',
            2,
          ),
        ),
      );
      expect(await File('${root.path}/new.png').exists(), isFalse);
      expect(await existing.readAsString(), 'keep');
    });
  });
}
