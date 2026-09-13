import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:marionette_agent_util/src/recording/web_recorder.dart';
import 'package:marionette_agent_util/src/recording/web_target.dart';
import 'package:test/test.dart';

class Native implements ScreenRecorder {
  int starts = 0;
  final handles = <Capture>[];
  PlatformException? error;
  Completer<void>? gate;
  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) async {
    starts++;
    expect(target.platform, RecordingPlatform.macos);
    expect(target.device, '1');
    expect(path, endsWith('.mov'));
    await gate?.future;
    if (error != null) throw error!;
    final capture = Capture(path);
    handles.add(capture);
    return capture;
  }
}

class Capture implements RecordingHandle {
  Capture(this.path);
  final String path;
  final done = Completer<void>();
  Completer<void>? stopGate;
  int stops = 0;
  bool fail = false;
  @override
  bool get isRunning => !done.isCompleted;
  @override
  Future<void> get ended => done.future;
  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    if (!done.isCompleted) done.complete();
    if (fail) {
      throw const PlatformException('IO_ERROR', 'native capture failed');
    }
    await File(path).writeAsString('native whole-display movie');
  }

  @override
  Future<void> abort() async {
    if (!done.isCompleted) done.complete();
    if (stopGate != null && !stopGate!.isCompleted) stopGate!.complete();
  }
}

Matcher code(String value) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', value));
void main() {
  test('strict explicit target and shared physical display identity', () {
    const endpoint = 'ws://127.0.0.1:9222/devtools/page/ABC123';
    const valid = 'display:1@$endpoint';
    expect(WebRecordingTarget.parse(valid), isNotNull);
    const web = RecordingTarget(RecordingPlatform.web, valid);
    expect(web.key, const RecordingTarget(RecordingPlatform.macos, '1').key);
    expect(web.extension, '.mov');
    validateTarget(web, '/tmp/video.mov');
    expect(
      () => validateTarget(web, '/tmp/video.mp4'),
      code('INVALID_ARGUMENT'),
    );
    for (final bad in [
      endpoint,
      'display:0@$endpoint',
      'display:01@$endpoint',
      valid.replaceFirst('127.0.0.1', 'localhost'),
      valid.replaceFirst('127.0.0.1', '192.168.1.2'),
      valid.replaceFirst('9222', '65536'),
      valid.replaceFirst('9222', '09222'),
      valid.replaceFirst('ws:', 'wss:'),
      '$valid?secret=1',
      '$valid#fragment',
      '$valid\n',
      valid.replaceFirst('/page/', '/browser/'),
      valid.replaceFirst('ABC123', '%41BC123'),
      valid.replaceFirst('127.0.0.1', 'user@127.0.0.1'),
    ]) {
      expect(WebRecordingTarget.parse(bad), isNull, reason: bad);
    }
  });
  group('Chrome protocol and native recording lifecycle', () {
    late HttpServer server;
    late Directory dir;
    late Native native;
    late RecordingManager manager;
    final sockets = <WebSocket>[];
    final commands = <String>[];
    String product = 'Chrome/150.0', type = 'page';
    String? reject;
    bool hang = false;
    DateTime deadline([int ms = 3000]) =>
        DateTime.now().add(Duration(milliseconds: ms));
    RecordingTarget target([String id = 'ABC123']) => RecordingTarget(
      RecordingPlatform.web,
      'display:1@ws://127.0.0.1:${server.port}/devtools/page/$id',
    );
    Future<Map<String, Object?>> start({
      String owner = 'a',
      String name = 'video',
      int ms = 3000,
      String id = 'ABC123',
    }) => manager.start(
      owner: owner,
      target: target(id),
      path: '${dir.path}/$name.mov',
      deadline: deadline(ms),
    );
    setUp(() async {
      sockets.clear();
      commands.clear();
      product = 'Chrome/150.0';
      type = 'page';
      reject = null;
      hang = false;
      dir = await Directory.systemTemp.createTemp('web-record-test-');
      native = Native();
      manager = RecordingManager(
        recorder: WebScreenRecorder(native, captureAllowed: () => true),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((dynamic raw) {
          final message = jsonDecode(raw as String) as Map;
          final method = message['method'] as String;
          commands.add(method);
          if (hang) return;
          socket.add(
            jsonEncode({
              'id': message['id'],
              if (reject == method)
                'error': {
                  'code': -32000,
                  'message': 'denied secret page contents',
                }
              else
                'result': switch (method) {
                  'Browser.getVersion' => {'product': product},
                  'Target.getTargetInfo' => {
                    'targetInfo': {
                      'targetId': request.uri.pathSegments.last,
                      'type': type,
                    },
                  },
                  _ => <String, Object?>{},
                },
            }),
          );
        });
      });
    });
    tearDown(() async {
      await manager.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    test('normal stop and duplicate stop use native movie', () async {
      expect((await start())['recordingState'], 'recording');
      expect(manager.status('a')['recordingState'], 'recording');
      expect(commands, [
        'Browser.getVersion',
        'Target.getTargetInfo',
        'Inspector.enable',
      ]);
      expect(
        (await manager.stop('a', deadline()))['recordingState'],
        'stopped',
      );
      await manager.stop('a', deadline());
      expect(native.handles.single.stops, 1);
      expect(
        await File('${dir.path}/video.mov').readAsString(),
        'native whole-display movie',
      );
    });
    test('close finalizes and releases session', () async {
      await start();
      expect(
        (await manager.close('a', deadline()))!['recordingState'],
        'stopped',
      );
      expect(manager.contains('a'), false);
    });
    test('tab closure fails with recovery movie', () async {
      await start();
      await sockets.single.close();
      await native.handles.single.ended;
      await expectLater(manager.stop('a', deadline()), code('CONNECTION_LOST'));
      expect(manager.status('a')['recordingState'], 'failed');
      expect(await File('${dir.path}/video.mov').length(), 0);
      expect(
        await File(manager.status('a')['recoveryPath'] as String).exists(),
        true,
      );
    });
    test('tab crash fails', () async {
      await start();
      sockets.single.add(jsonEncode({'method': 'Inspector.targetCrashed'}));
      await native.handles.single.ended;
      await expectLater(manager.stop('a', deadline()), code('CONNECTION_LOST'));
    });
    test('native abnormal termination propagates', () async {
      await start();
      native.handles.single.fail = true;
      native.handles.single.done.complete();
      await expectLater(manager.stop('a', deadline()), code('IO_ERROR'));
    });
    test(
      'permission preflight denies before Chrome or native startup',
      () async {
        await manager.dispose();
        manager = RecordingManager(
          recorder: WebScreenRecorder(native, captureAllowed: () => false),
        );
        await expectLater(start(), code('IO_ERROR'));
        expect(sockets, isEmpty);
        expect(native.starts, 0);
        expect(await File('${dir.path}/video.mov').exists(), false);
      },
    );
    test('permission refusal cleans output reservation', () async {
      native.error = const PlatformException(
        'IO_ERROR',
        'Screen recording permission denied',
        hint: 'Enable Screen Recording in macOS Settings',
      );
      await expectLater(start(), code('IO_ERROR'));
      expect(await File('${dir.path}/video.mov').exists(), false);
      expect(manager.contains('a'), false);
    });
    test('missing native tool is unsupported with no reservation', () async {
      native.error = const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Recording tool unavailable',
      );
      await expectLater(start(), code('UNSUPPORTED_CAPABILITY'));
      expect(await File('${dir.path}/video.mov').exists(), false);
    });
    test(
      'protocol refusal redacts remote content before native startup',
      () async {
        reject = 'Inspector.enable';
        await expectLater(
          start(),
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'IO_ERROR')
                .having((e) => e.toString(), 'safe', isNot(contains('secret'))),
          ),
        );
        expect(native.starts, 0);
      },
    );
    test('unsupported browser and headless rejected before capture', () async {
      for (final value in ['Firefox/150', 'HeadlessChrome/150']) {
        product = value;
        await expectLater(start(), code('UNSUPPORTED_CAPABILITY'));
      }
      expect(native.starts, 0);
    });
    test('non-page target rejected', () async {
      type = 'worker';
      await expectLater(start(), code('INVALID_ARGUMENT'));
      expect(native.starts, 0);
    });
    test('startup timeout releases reservation after cleanup', () async {
      hang = true;
      await expectLater(start(ms: 60), code('TIMEOUT'));
      await manager.dispose();
      expect(native.starts, 0);
      expect(await File('${dir.path}/video.mov').exists(), false);
    });
    test('disconnect during native startup stops late handle', () async {
      native.gate = Completer<void>();
      final assertion = expectLater(start(), code('CONNECTION_LOST'));
      while (native.starts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await sockets.single.close();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      native.gate!.complete();
      await assertion;
      expect(native.handles.single.isRunning, false);
      expect(await File('${dir.path}/video.mov').exists(), false);
    });
    test('different tabs and macos share physical-display lock', () async {
      await start();
      await expectLater(
        start(owner: 'b', name: 'other', id: 'DEF456'),
        code('SESSION_CONFLICT'),
      );
      await expectLater(
        manager.start(
          owner: 'b',
          target: const RecordingTarget(RecordingPlatform.macos, '1'),
          path: '${dir.path}/native.mov',
          deadline: deadline(),
        ),
        code('SESSION_CONFLICT'),
      );
      expect(native.starts, 1);
    });
    test('stop timeout keeps lock until termination', () async {
      await start();
      final gate = native.handles.single.stopGate = Completer<void>();
      await expectLater(manager.stop('a', deadline(10)), code('TIMEOUT'));
      expect(manager.status('a')['recordingState'], 'stopping');
      await expectLater(
        start(owner: 'b', name: 'other'),
        code('SESSION_CONFLICT'),
      );
      gate.complete();
      await manager.stop('a', deadline());
      await start(owner: 'b', name: 'other');
    });
    test('existing files directories symlinks protected', () async {
      final existing = File('${dir.path}/existing.mov');
      await existing.writeAsString('keep');
      await Directory('${dir.path}/directory.mov').create();
      await Link('${dir.path}/link.mov').create(existing.path);
      for (final name in ['existing', 'directory', 'link']) {
        await expectLater(start(name: name), code('IO_ERROR'));
      }
      expect(native.starts, 0);
      expect(await existing.readAsString(), 'keep');
    });
  }, skip: !Platform.isMacOS);
}
