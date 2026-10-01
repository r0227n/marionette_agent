import 'dart:async';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';

class App implements RunningApplication {
  final done = Completer<int>();
  int stops = 0;
  @override
  Uri get uri => Uri.parse('http://127.0.0.1:12345/secret/');
  @override
  Map<String, Object?> get description => {
    'platform': 'tester',
    'state': done.isCompleted ? 'exited' : 'running',
  };
  @override
  Future<int> get exited => done.future;
  @override
  Future<void> stop() async {
    stops++;
    if (!done.isCompleted) done.complete(0);
  }
}

class Launcher implements ApplicationLauncher {
  final app = App();
  int starts = 0;
  bool failDispose = false;
  @override
  Future<RunningApplication> start(
    LaunchOptions options,
    DateTime deadline,
  ) async {
    starts++;
    return app;
  }

  @override
  Future<void> dispose() async {
    if (!app.done.isCompleted) await app.stop();
    if (failDispose) throw StateError("cleanup failed");
  }
}

void main() {
  final params = {'platform': 'tester', 'project': '/project'};
  late Launcher launcher;
  late SessionManager manager;
  Future<Result> call(String command, {Json? args, Json? policy}) =>
      manager.handle(
        Request(
          requestId: 'test',
          session: 'launch',
          command: command,
          params: args ?? {},
          policy: policy,
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
  setUp(() {
    launcher = Launcher();
    manager = SessionManager(
      FakeBackend.new,
      coreCommands(),
      launcher: launcher,
    );
  });
  tearDown(() => manager.dispose());
  test(
    'launch connects via the existing backend and close stops its app',
    () async {
      final result = await call('launch', args: params);
      expect(result.error, isNull);
      expect(result.data!['state'], 'connected');
      expect(result.data!['application'], containsPair('platform', 'tester'));
      expect(result.toJson().toString(), isNot(contains('/secret/')));
      expect((await call('snapshot')).error, isNull);
      expect(
        (await call('launch', args: params)).error!.code,
        'SESSION_CONFLICT',
      );
      expect(launcher.starts, 1);
      expect((await call('close')).error, isNull);
      expect(launcher.app.stops, 1);
    },
  );
  test(
    'failed initial observation closes the owned app and releases the session',
    () async {
      final backend = FakeBackend()
        ..hooks['inspect'] = () async {
          throw const AgentError(
            'UNSUPPORTED_CAPABILITY',
            'Binding unavailable',
          );
        };
      manager = SessionManager(
        () => backend,
        coreCommands(),
        launcher: launcher,
      );
      final result = await call('launch', args: params);
      expect(result.error!.code, 'UNSUPPORTED_CAPABILITY');
      expect(launcher.app.stops, 1);
      expect(manager.sessions, isEmpty);
      expect(backend.connected, isFalse);
    },
  );
  test('external connect does not acquire application ownership', () async {
    expect(
      (await call('connect', args: {'uri': 'http://localhost:99/'})).error,
      isNull,
    );
    expect((await call('close')).error, isNull);
    expect(launcher.starts, 0);
    expect(launcher.app.stops, 0);
  });
  test(
    'close observes disconnect failure even when app exit retires first',
    () async {
      final backend = FakeBackend();
      manager = SessionManager(
        () => backend,
        coreCommands(),
        launcher: launcher,
      );
      expect((await call('launch', args: params)).error, isNull);
      backend.hooks['disconnect'] = () async =>
          throw StateError('private detail');
      final result = await call('close');
      expect(result.error?.code, 'BACKEND_ERROR');
      expect(result.error?.outcome, Outcome.failed);
      expect(backend.calls.where((call) => call == 'disconnect'), hasLength(1));
      expect(manager.sessions, isEmpty);
    },
  );
  test('policy denies and confirms launch before creating processes', () async {
    final denied = await call(
      'launch',
      args: params,
      policy: {
        'deny': ['launch'],
      },
    );
    expect(denied.error!.code, 'ACTION_DENIED');
    expect(launcher.starts, 0);
    manager = SessionManager(
      FakeBackend.new,
      coreCommands(),
      launcher: launcher,
    );
    final pending = await call(
      'launch',
      args: params,
      policy: {
        'confirm': ['launch'],
      },
    );
    expect(pending.error!.code, 'CONFIRMATION_REQUIRED');
    expect(launcher.starts, 0);
    expect(
      (await call(
        'confirm',
        args: {'id': pending.error!.details!['confirmationId']},
      )).error,
      isNull,
    );
    expect(launcher.starts, 1);
  });
  test('process exit retires the observation without relaunching', () async {
    await call('launch', args: params);
    await call('snapshot');
    launcher.app.done.complete(17);
    await Future<void>.delayed(Duration.zero);
    expect(manager.sessions['launch']!.status, 'disconnected');
    expect(manager.sessions['launch']!.observation, isNull);
    expect(launcher.starts, 1);
    await call('close');
  });
  test('close all stops managed applications', () async {
    await call('launch', args: params);
    expect((await call('close', args: {'all': true})).error, isNull);
    expect(launcher.app.stops, 1);
  });
  test(
    'dispose retires backend sessions even when app cleanup fails',
    () async {
      final backend = FakeBackend();
      manager = SessionManager(
        () => backend,
        coreCommands(),
        launcher: launcher,
      );
      await call('launch', args: params);
      launcher.failDispose = true;
      try {
        await expectLater(manager.dispose(), throwsStateError);
        expect(manager.sessions, isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(backend.connected, isFalse);
      } finally {
        launcher.failDispose = false;
      }
    },
  );
  test('parser shares util validation and rejects wrong platform options', () {
    final parser = CliParser();
    expect(
      parser.parse([
        'launch',
        './example',
        '--platform',
        'tester',
      ]).params['project'],
      endsWith('/example'),
    );
    for (final args in [
      ['launch', './example'],
      ['launch', './example', '--platform', 'ios'],
      ['launch', './example', '--platform', 'tester', '--port', '5554'],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });
}
