import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not become true');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory directory;
  late RuntimeDirectory runtime;
  setUp(() async {
    directory = await Directory('/tmp').createTemp('mra-idle-');
    await Process.run('chmod', ['700', directory.path]);
    runtime = await RuntimeDirectory.prepare(directory: directory.path);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('expiry discards every session and releases socket and lifetime lock; reconnect is explicit', () async {
    final backends = <FakeBackend>[];
    final manager = SessionManager(() {
      final b = FakeBackend()
        ..elements = [ElementInfo(key: 'button', type: 'Button')];
      backends.add(b);
      return b;
    }, coreCommands());
    final server = DaemonServer(runtime, manager, idleTimeoutMs: 200);
    final running = server.run();
    addTearDown(() async {
      await server.close();
      await running;
    });
    await eventually(() => File(runtime.metadata).existsSync());
    final client = DaemonClient(runtime);
    for (final name in ['a', 'b']) {
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
      expect(
        (await client.send(request('snapshot', session: name))).exitCode,
        0,
      );
    }
    await running.timeout(const Duration(seconds: 3));
    expect(manager.sessions, isEmpty);
    expect(backends.every((b) => !b.connected), isTrue);
    expect(File(runtime.metadata).existsSync(), isFalse);
    expect(
      FileSystemEntity.typeSync(runtime.socket),
      FileSystemEntityType.notFound,
    );
    final lock = await runtime.lock(
      'daemon.lock',
      DateTime.now().add(const Duration(seconds: 1)),
    );
    await lock.unlock();
    await lock.close();
    final response = await client.send(request('tap', params: {'ref': '@e1'}));
    expect(response.error!.code, 'NOT_CONNECTED');
    expect(response.error!.outcome, Outcome.notSent);
    // Explicit connect can start a fresh daemon using the same runtime.
    final restarted = DaemonServer(
      runtime,
      SessionManager(FakeBackend.new, coreCommands()),
      idleTimeoutMs: 0,
    );
    final restartedRun = restarted.run();
    await eventually(() => File(runtime.metadata).existsSync());
    expect(
      (await client.send(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      )).exitCode,
      0,
    );
    expect(
      (await client.send(request('tap', params: {'ref': '@e1'}))).error!.code,
      'STALE_REF',
    );
    await client.send(request('close'));
    await restartedRun;
  });

  test(
    'zero disables expiry and an explicit mismatch never dispatches mutation',
    () async {
      final backend = FakeBackend()
        ..elements = [ElementInfo(key: 'button', type: 'Button')];
      final server = DaemonServer(
        runtime,
        SessionManager(() => backend, coreCommands()),
        idleTimeoutMs: 0,
      );
      final running = server.run();
      addTearDown(() async {
        await server.close();
        await running;
      });
      await eventually(() => File(runtime.metadata).existsSync());
      final client = DaemonClient(runtime);
      await client.send(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final mismatch = await DaemonClient(runtime, idleTimeoutMs: 100).send(
        request(
          'tap',
          params: {
            'selector': {'kind': 'key', 'value': 'button'},
          },
        ),
      );
      expect(mismatch.error!.code, 'INVALID_ARGUMENT');
      expect(mismatch.error!.outcome, Outcome.notSent);
      expect(backend.calls, isNot(contains('tap')));
      expect((await client.send(request('snapshot'))).exitCode, 0);
      expect(
        jsonDecode(
          await File(runtime.metadata).readAsString(),
        )['idleTimeoutMs'],
        0,
      );
    },
  );

  test('running and queued requests outlive idle timeout; full idle interval starts after completion', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final backend = FakeBackend()
      ..elements = [ElementInfo(key: 'button', type: 'Button')];
    backend.hooks['inspect'] = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final manager = SessionManager(() => backend, coreCommands());
    final server = DaemonServer(runtime, manager, idleTimeoutMs: 200);
    final running = server.run();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close();
      await running;
    });
    await eventually(() => File(runtime.metadata).existsSync());
    final client = DaemonClient(runtime);
    await client.send(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
    final first = client.send(request('snapshot'));
    await entered.future;
    final queued = client.send(request('snapshot'));
    await eventually(() => manager.sessions['a']!.pending == 2);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(File(runtime.metadata).existsSync(), isTrue);
    release.complete();
    expect((await first).exitCode, 0);
    expect((await queued).exitCode, 0);
    await Future<void>.delayed(const Duration(milliseconds: 75));
    expect(File(runtime.metadata).existsSync(), isTrue);
    await running.timeout(const Duration(seconds: 3));
  });

  test(
    'timed-out queue entry still prevents shutdown until the queue drains',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final backend = FakeBackend();
      backend.hooks['inspect'] = () async {
        entered.complete();
        await release.future;
      };
      final manager = SessionManager(() => backend, coreCommands());
      final server = DaemonServer(runtime, manager, idleTimeoutMs: 150);
      final running = server.run();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await server.close();
        await running;
      });
      await eventually(() => File(runtime.metadata).existsSync());
      final client = DaemonClient(runtime);
      await client.send(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      final active = client.send(request('snapshot'));
      await entered.future;
      final expired = await client.send(request('snapshot', ms: 50));
      expect(expired.error!.code, 'TIMEOUT');
      expect(expired.error!.outcome, Outcome.notSent);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File(runtime.metadata).existsSync(), isTrue);
      release.complete();
      expect((await active).exitCode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(File(runtime.metadata).existsSync(), isTrue);
      await running.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'periodic health probes do not renew user inactivity indefinitely',
    () async {
      final server = DaemonServer(
        runtime,
        SessionManager(FakeBackend.new, coreCommands()),
        idleTimeoutMs: 1300,
      );
      final running = server.run();
      addTearDown(() async {
        await server.close();
        await running;
      });
      await eventually(() => File(runtime.metadata).existsSync());
      await DaemonClient(runtime)
          .send(request('connect', params: {'uri': 'http://localhost:1/'}));
      await running.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'repeated passive doctor handshakes do not renew idle lifetime',
    () async {
      final server = DaemonServer(
        runtime,
        SessionManager(FakeBackend.new, coreCommands()),
        idleTimeoutMs: 600,
      );
      var ended = false;
      final running = server.run().whenComplete(() {
        ended = true;
      });
      addTearDown(() async {
        await server.close();
        await running;
      });
      await eventually(() => File(runtime.metadata).existsSync());
      final watch = Stopwatch()..start();
      var handshakes = 0;
      while (!ended && watch.elapsed < const Duration(milliseconds: 1500)) {
        Socket? socket;
        try {
          socket = await Socket.connect(
            InternetAddress(runtime.socket, type: InternetAddressType.unix),
            0,
          );
          expect(
            (await decodeFrames(socket).first)['protocolVersion'],
            protocolVersion,
          );
          handshakes++;
        } on SocketException {
          break;
        } finally {
          socket?.destroy();
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(handshakes, greaterThan(1));
      expect(
        ended,
        true,
        reason: 'Passive handshakes must not keep an idle daemon alive',
      );
    },
  );

  test(
    'queue drain arms idle after a handshake disconnects during a health probe',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final backend = FakeBackend();
      final manager = SessionManager(() => backend, coreCommands());
      final server = DaemonServer(runtime, manager, idleTimeoutMs: 200);
      final running = server.run();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await server.close();
        await running;
      });
      await eventually(() => File(runtime.metadata).existsSync());
      final client = DaemonClient(runtime);
      await client.send(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      backend.hooks['checkConnection'] = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final probe = manager.probe();
      await entered.future;
      final mismatch = await DaemonClient(
        runtime,
        idleTimeoutMs: 0,
      ).send(request('snapshot'));
      expect(mismatch.error!.code, 'INVALID_ARGUMENT');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(File(runtime.metadata).existsSync(), isTrue);
      release.complete();
      await probe;
      await running.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'concurrent startup commits one immutable configuration under launch lock',
    () async {
      Future<ProcessResult> cli(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['test/support/fake_cli.dart', '--json', ...args],
        environment: {'MARIONETTE_AGENT_RUNTIME_DIR': directory.path},
      );
      final responses = await Future.wait([
        cli([
          '--idle-timeout',
          '0',
          '--session',
          'a',
          'connect',
          'http://localhost:1/',
        ]),
        cli([
          '--idle-timeout',
          '60000',
          '--session',
          'b',
          'connect',
          'http://localhost:2/',
        ]),
      ]);
      try {
        expect(responses.map((r) => r.exitCode).toList()..sort(), [0, 2]);
        final loser = asJson(
          jsonDecode(
            responses.singleWhere((r) => r.exitCode == 2).stdout as String,
          ),
        );
        expect(asJson(loser['error'])['code'], 'INVALID_ARGUMENT');
        expect(asJson(loser['error'])['outcome'], 'not_sent');
        final metadata = asJson(
          jsonDecode(await File(runtime.metadata).readAsString()),
        );
        final winner = responses[0].exitCode == 0 ? 0 : 60000;
        expect(metadata['idleTimeoutMs'], winner);
        final list = await cli(['session', 'list']);
        expect(
          (asJson(asJson(jsonDecode(list.stdout as String))['data'])['sessions']
                  as List)
              .length,
          1,
        );
      } finally {
        await cli(['--session', 'a', 'close']);
        await cli(['--session', 'b', 'close']);
        await eventually(() => !File(runtime.metadata).existsSync());
      }
    },
  );
}
