import 'dart:async';
import 'dart:io';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

void main() {
  test('parser accepts all and rejects explicit session on either side', () {
    final parser = CliParser();
    expect(parser.parse(['close', '--all']).params, {'all': true});
    expect(parser.parse(['close', '--all']).resultSession, isNull);
    for (final args in [
      ['--session', 'default', 'close', '--all'],
      ['close', '--all', '--session', 'a'],
      ['close', '--all', '--all'],
      ['close', '--all', 'extra'],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });

  late Directory directory;
  late RuntimeDirectory runtime;
  late SessionManager manager;
  late DaemonServer server;
  late DaemonClient client;
  late Future<void> running;
  late List<FakeBackend> backends;

  setUp(() async {
    directory = await Directory('/tmp').createTemp('mra-i6-test-');
    runtime = await RuntimeDirectory.prepare(directory: directory.path);
    backends = [];
    manager = SessionManager(() {
      final backend = FakeBackend();
      backends.add(backend);
      return backend;
    }, coreCommands());
    server = DaemonServer(runtime, manager);
    running = server.run();
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!File(runtime.metadata).existsSync()) {
      if (DateTime.now().isAfter(end)) fail('Daemon did not start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    client = DaemonClient(runtime);
    expect(
      (await client.send(request('session', params: {'action': 'list'})))
          .exitCode,
      0,
    );
  });
  tearDown(() async {
    await server.close();
    await running;
    await directory.delete(recursive: true);
  });
  Future<void> connect(String name) async {
    expect(
      (await client.send(
        request(
          'connect',
          session: name,
          params: {'uri': 'http://localhost:${name == 'a' ? 1 : 2}/'},
        ),
      )).exitCode,
      0,
    );
  }

  Future<void> released() async {
    await running.timeout(const Duration(seconds: 2));
    expect(manager.sessions, isEmpty);
    expect(
      FileSystemEntity.typeSync(runtime.socket),
      FileSystemEntityType.notFound,
    );
    expect(File(runtime.metadata).existsSync(), isFalse);
    final lock = await runtime.lock(
      'daemon.lock',
      DateTime.now().add(const Duration(seconds: 1)),
    );
    await lock.unlock();
    await lock.close();
  }

  test(
    'IPC closes two sessions, refs, socket and lock; absent is idempotent',
    () async {
      await connect('a');
      await connect('b');
      await client.send(request('snapshot', session: 'a'));
      await client.send(request('snapshot', session: 'b'));
      final sessions = manager.sessions.values.toList();
      expect(sessions.every((s) => s.observation != null), isTrue);
      final result = await client.send(request('close', params: {'all': true}));
      expect(result.exitCode, 0);
      expect(result.session, isNull);
      expect((result.data!['sessions'] as List).length, 2);
      expect(
        sessions.every((s) => s.observation == null && s.backend == null),
        isTrue,
      );
      expect(backends.every((b) => !b.connected), isTrue);
      await released();
      expect(
        (await client.send(request('close', params: {'all': true}))).data,
        {'closed': true, 'sessions': []},
      );
      expect(
        (await client.send(request('snapshot'))).error?.code,
        'NOT_CONNECTED',
      );
    },
  );

  test(
    'IPC returns partial disconnect failure and text includes session results',
    () async {
      await connect('a');
      await connect('b');
      backends[0].hooks['disconnect'] = () async {
        throw StateError('private backend detail');
      };
      final result = await client.send(request('close', params: {'all': true}));
      expect(result.exitCode, 1);
      expect(result.error?.outcome, Outcome.failed);
      final rows = result.error!.details!['sessions'] as List;
      expect((rows[0] as Map)['ok'], false);
      expect((rows[1] as Map)['ok'], true);
      final text = render(result, json: false);
      expect(text, contains('"session": "a"'));
      expect(text, isNot(contains('Workflow')));
      expect(text, isNot(contains('private backend detail')));
      await released();
    },
  );

  test('IPC deadline interrupts sent action, rejects queue and racing connect without replay', () async {
    await connect('a');
    await connect('b');
    final entered = Completer<void>();
    final finish = Completer<void>();
    backends[0].hooks['tap'] = () {
      entered.complete();
      return finish.future;
    };
    final action = client.send(
      request('tap', params: {'x': 1.0, 'y': 1.0}, ms: 5000),
    );
    await entered.future;
    final queued = client.send(
      request('tap', params: {'x': 1.0, 'y': 1.0}, ms: 5000),
    );
    while (manager.sessions['a']!.pending < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final closing = client.send(
      request('close', params: {'all': true}, ms: 1000),
    );
    while (!manager.stopping) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final racing = await client.send(
      request('connect', session: 'c', params: {'uri': 'http://localhost:3/'}),
    );
    expect(racing.error?.outcome, Outcome.notSent);
    final result = await closing;
    expect(result.exitCode, 5);
    final rows = result.error!.details!['sessions'] as List;
    expect((rows[0] as Map)['ok'], false);
    expect((rows[1] as Map)['ok'], true);
    expect((await action).error?.outcome, Outcome.unknown);
    expect((await queued).error?.outcome, Outcome.notSent);
    expect(backends[0].calls.where((s) => s == 'tap').length, 1);
    finish.complete();
    await released();
  });

  test(
    'connect reserved before close is drained and disposed after completion',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      // This backend represents a connection reserved at intake but not established.
      final backend = FakeBackend();
      backend.hooks['connect'] = () {
        entered.complete();
        return finish.future;
      };
      await server.close();
      await running;
      manager = SessionManager(() => backend, coreCommands());
      server = DaemonServer(runtime, manager);
      running = server.run();
      while (!File(runtime.metadata).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final connecting = client.send(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      await entered.future;
      final closing = client.send(request('close', params: {'all': true}));
      while (!manager.stopping) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      finish.complete();
      expect((await connecting).exitCode, 0);
      expect((await closing).exitCode, 0);
      expect(backend.connected, false);
      await released();
    },
  );

  test('IPC stalls disconnect only until close deadline', () async {
    await connect('a');
    final finish = Completer<void>();
    backends[0].hooks['disconnect'] = () => finish.future;
    final result = await client.send(
      request('close', params: {'all': true}, ms: 1000),
    );
    expect(result.exitCode, 5);
    expect(result.error?.outcome, Outcome.unknown);
    await released();
    finish.complete();
  });

  test('IPC non-reading client cannot retain shutdown lock', () async {
    await connect('a');
    await connect('b');
    final socket = await Socket.connect(
      InternetAddress(runtime.socket, type: InternetAddressType.unix),
      0,
    );
    socket.add(encodeFrame(request('close', params: {'all': true}).toJson()));
    await socket.flush();
    await released();
    socket.destroy();
  });

  test(
    'empty running daemon closes and invalid params do not stop intake',
    () async {
      final invalidResult = await client.send(
        request('close', params: {'all': true, 'extra': 1}),
      );
      expect(invalidResult.exitCode, 2);
      expect(manager.stopping, false);
      expect(
        (await client.send(request('close', params: {'all': true}))).data,
        {'closed': true, 'sessions': []},
      );
      await released();
    },
  );
}
