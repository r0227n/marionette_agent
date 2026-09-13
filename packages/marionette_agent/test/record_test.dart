import 'dart:async';
import 'dart:io';

import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/recording/record_service.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

class Recorder implements ScreenRecorder {
  int starts = 0;
  Handle? lastHandle;
  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) async {
    starts++;
    return lastHandle = Handle(path);
  }
}

class Handle implements RecordingHandle {
  Handle(this.path);
  final String path;
  final done = Completer<void>();
  bool fail = false;
  @override
  Future<void> abort() async {
    if (!done.isCompleted) done.complete();
  }

  @override
  Future<void> get ended => done.future;
  @override
  bool get isRunning => !done.isCompleted;
  @override
  Future<void> stop() async {
    await File(path).writeAsString('video fixture');
    if (!done.isCompleted) done.complete();
    if (fail) throw const PlatformException('IO_ERROR', 'finalization failed');
  }
}

void main() {
  late Directory dir;
  late SessionManager manager;
  late Recorder recorder;
  var emptied = false;
  Future<Result> call(
    String command, {
    Json params = const {},
    String session = 'a',
  }) => manager.handle(
    Request(
      requestId: 'record-test',
      session: session,
      command: command,
      params: params,
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    ),
  );
  Json start([String platform = 'android']) => {
    'action': 'start',
    'platform': platform,
    'device': 'emulator-5556',
    'path': '${dir.path}/video.mp4',
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('record-cli-');
    emptied = false;
    recorder = Recorder();
    manager = SessionManager(
      FakeBackend.new,
      coreCommands(),
      recordings: RecordService(manager: RecordingManager(recorder: recorder)),
    )..onEmpty = () => emptied = true;
  });
  tearDown(() async {
    await manager.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'record-only session persists, allows connect and preserves refs',
    () async {
      expect((await call('record', params: start())).exitCode, 0);
      expect(emptied, false);
      expect(
        (await call(
          'record',
          params: {'action': 'status'},
        )).data!['recordingState'],
        'recording',
      );
      expect(
        (await call(
          'connect',
          params: {'uri': 'http://localhost:1/'},
        )).exitCode,
        0,
      );
      final observation = Object();
      manager.sessions['a']!.observation = observation;
      expect((await call('record', params: {'action': 'stop'})).exitCode, 0);
      expect(manager.sessions['a']!.observation, same(observation));
      expect(emptied, false);
      final closed = await call('close');
      expect(
        closed.data!['recording'],
        containsPair('recordingState', 'stopped'),
      );
      expect(emptied, true);
    },
  );
  test(
    'close finalizes active recording and other sessions remain alive',
    () async {
      await call('record', params: start());
      await call(
        'connect',
        session: 'b',
        params: {'uri': 'http://localhost:2/'},
      );
      expect((await call('close')).exitCode, 0);
      expect(
        await File('${dir.path}/video.mp4').readAsString(),
        'video fixture',
      );
      expect(emptied, false);
      expect(manager.sessions.containsKey('b'), true);
    },
  );
  test('unsupported platforms throw through CLI contract without launching tools', () async {
    // Keep a session alive so independent invalid requests share this manager.
    await call('connect', params: {'uri': 'http://localhost:1/'});
    for (final platform in ['linux', 'windows']) {
      final result = await call('record', params: start(platform));
      expect(result.error!.code, 'UNSUPPORTED_CAPABILITY');
      expect(result.exitCode, 6);
    }
    expect(recorder.starts, 0);
    expect(await File('${dir.path}/video.mp4').exists(), false);
  });
  test(
    'web uses common session API and keeps VM operations available',
    () async {
      final params = {
        ...start('web'),
        'device': 'display:1@ws://127.0.0.1:9222/devtools/page/ABC123',
        'path': '${dir.path}/web.mov',
      };
      expect((await call('record', params: params)).exitCode, 0);
      expect(
        (await call(
          'connect',
          params: {'uri': 'http://localhost:1/'},
        )).exitCode,
        0,
      );
      expect((await call('snapshot')).exitCode, 0);
      final observation = manager.sessions['a']!.observation;
      expect(
        (await call(
          'record',
          params: {'action': 'status'},
        )).data!['recordingState'],
        'recording',
      );
      expect(manager.sessions['a']!.observation, same(observation));
      final conflict = await call(
        'record',
        session: 'b',
        params: {
          ...start('macos'),
          'device': '1',
          'path': '${dir.path}/conflict.mov',
        },
      );
      expect(conflict.error!.code, 'SESSION_CONFLICT');
      expect(
        (await call('close')).data!['recording'],
        containsPair('recordingState', 'stopped'),
      );
    },
  );
  test(
    'web parser accepts explicit display/page and rejects invalid targets',
    () {
      final parser = CliParser();
      const device = 'display:1@ws://127.0.0.1:9222/devtools/page/ABC123';
      final parsed = parser.parse([
        'record',
        'start',
        'web.mov',
        '--platform',
        'web',
        '--device',
        device,
      ]);
      expect(parsed.params['device'], device);
      expect(parsed.params['path'], File('web.mov').absolute.path);
      expect(
        () => parser.parse([
          'record',
          'start',
          'web.mp4',
          '--platform',
          'web',
          '--device',
          device,
        ]),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
        ),
      );
    },
  );
  test('VM connection retirement does not stop device recording', () async {
    await call('connect', params: {'uri': 'http://localhost:1/'});
    await call('record', params: start());
    manager.sessions['a']!.discard();
    expect(
      (await call(
        'record',
        params: {'action': 'status'},
      )).data!['recordingState'],
      'recording',
    );
    expect((await call('record', params: {'action': 'stop'})).exitCode, 0);
    expect(manager.sessions['a']!.status, 'disconnected');
  });
  test('confirmed stop failure uses failed outcome', () async {
    await call('record', params: start());
    recorder.lastHandle!.fail = true;

    final result = await call('record', params: {'action': 'stop'});

    expect(result.error!.code, 'IO_ERROR');
    expect(result.error!.outcome, Outcome.failed);
  });
  test('daemon revalidates unknown parameters before starting', () async {
    final result = await call('record', params: {...start(), 'extra': true});
    expect(result.error!.code, 'INVALID_ARGUMENT');
    expect(recorder.starts, 0);
  });
  test('parser separates start/stop options and resolves caller path', () {
    final parser = CliParser();
    final parsed = parser.parse([
      'record',
      'start',
      'demo.mp4',
      '--platform',
      'ios',
      '--device',
      '022CF629-91E1-48F0-816B-2D86B8CD1D38',
    ]);
    expect(parsed.params['path'], File('demo.mp4').absolute.path);
    for (final platform in ['linux', 'windows']) {
      expect(
        () => parser.parse([
          'record',
          'start',
          'demo.mp4',
          '--platform',
          platform,
          '--device',
          '1',
        ]),
        throwsA(
          isA<AgentError>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
    }
    for (final args in [
      ['record'],
      ['record', 'stop', 'extra'],
      ['record', 'start', 'demo.mp4'],
      ['record', 'status', '--device', 'id'],
      [
        'record',
        'start',
        'demo.mp4',
        '--platform',
        'ios',
        '--platform',
        'android',
        '--device',
        '022CF629-91E1-48F0-816B-2D86B8CD1D38',
      ],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });
}
