import 'dart:async';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/commands/registry.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

Request request(
  String command, {
  String session = 'a',
  Json params = const {},
  int ms = 2000,
}) => Request(
  requestId: 'test',
  session: session,
  command: command,
  params: params,
  deadline: DateTime.now().add(Duration(milliseconds: ms)),
);
void main() {
  late List<FakeBackend> backends;
  late CommandRegistry registry;
  late SessionManager manager;
  setUp(() {
    backends = [];
    registry = CommandRegistry();
    registry.register('read', (context, params) async {
      await context.read((b) => b.inspect());
      return {};
    });
    registry.register('write', (context, params) async {
      await context.performCoordinates(
        (b) => b.tap(CoordinateTarget(Point(1, 1))),
      );
      return {'requiresSnapshot': true};
    });
    manager = SessionManager(() {
      final b = FakeBackend();
      backends.add(b);
      return b;
    }, registry);
  });
  tearDown(() async {
    await manager.dispose();
  });
  Future<Result> connect([
    String name = 'a',
    String uri = 'http://localhost:1/token/',
  ]) => manager.handle(request('connect', session: name, params: {'uri': uri}));
  test('ownership, idempotent connect and redaction', () async {
    expect((await connect()).exitCode, 0);
    expect((await connect()).exitCode, 0);
    expect(backends.length, 1);
    expect((await connect('b')).error!.code, 'SESSION_CONFLICT');
    expect(
      (await connect('a', 'http://localhost:2/')).error!.code,
      'SESSION_CONFLICT',
    );
    final show = await manager.handle(
      request('session', params: {'action': 'show'}),
    );
    expect(show.data!['uri'].toString(), isNot(contains('token')));
    expect(
      (await manager.handle(request('read', session: 'absent'))).error!.code,
      'NOT_CONNECTED',
    );
  });
  test('same session serializes, other session remains independent', () async {
    await connect();
    await connect('b', 'http://localhost:2/');
    final gate = Completer<void>();
    final entered = Completer<void>();
    backends[0].hooks['inspect'] = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    final first = manager.handle(request('read'));
    await entered.future;
    final second = manager.handle(request('read'));
    expect((await manager.handle(request('read', session: 'b'))).exitCode, 0);
    expect(backends[0].calls.where((v) => v == 'inspect').length, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(backends[0].maxActive, 1);
  });
  test(
    'queued timeout never sends and does not discard active session',
    () async {
      await connect();
      final gate = Completer<void>();
      final entered = Completer<void>();
      backends[0].hooks['inspect'] = () {
        entered.complete();
        return gate.future;
      };
      final first = manager.handle(request('read'));
      await entered.future;
      final result = await manager.handle(request('write', ms: 20));
      expect(result.error!.code, 'TIMEOUT');
      expect(result.error!.outcome, Outcome.notSent);
      gate.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backends[0].calls, isNot(contains('tap')));
      expect(manager.sessions['a']!.status, 'connected');
    },
  );
  test(
    'sent timeout retires backend; late completion cannot affect reconnect',
    () async {
      await connect();
      final gate = Completer<void>();
      backends[0].hooks['tap'] = () => gate.future;
      final result = await manager.handle(request('write', ms: 30));
      expect(result.error!.code, 'TIMEOUT');
      expect(result.error!.outcome, Outcome.unknown);
      expect(manager.sessions['a']!.status, 'disconnected');
      expect((await connect()).exitCode, 0);
      final epoch = manager.sessions['a']!.epoch;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(manager.sessions['a']!.epoch, epoch);
      expect(manager.sessions['a']!.status, 'connected');
      expect(backends[0].calls.where((v) => v == 'tap').length, 1);
    },
  );
  test(
    'preflight disconnect is not_sent, dispatch disconnect is unknown',
    () async {
      await connect();
      backends[0].connected = false;
      final pre = await manager.handle(request('read'));
      expect(pre.error!.code, 'CONNECTION_LOST');
      expect(pre.error!.outcome, Outcome.notSent);
      await connect();
      backends.last.hooks['tap'] = () async {
        throw const AgentError('CONNECTION_LOST', 'lost');
      };
      final post = await manager.handle(request('write'));
      expect(post.error!.outcome, Outcome.unknown);
    },
  );
  test(
    'close followed by queued connect remains connected and owned',
    () async {
      await connect();
      final gate = Completer<void>();
      final entered = Completer<void>();
      backends[0].hooks['inspect'] = () {
        entered.complete();
        return gate.future;
      };
      final first = manager.handle(request('read'));
      await entered.future;
      final close = manager.handle(request('close'));
      final reconnect = connect();
      gate.complete();
      await first;
      expect((await close).exitCode, 0);
      expect((await reconnect).exitCode, 0);
      expect(manager.stopping, false);
      expect(manager.sessions['a']!.status, 'connected');
    },
  );
  test(
    'connection probe observes passive disconnect and invalidates',
    () async {
      await connect();
      manager.sessions['a']!.observation = Object();
      backends[0].connected = false;
      await manager.probe();
      expect(manager.sessions['a']!.status, 'disconnected');
      expect(manager.sessions['a']!.observation, isNull);
    },
  );
  test(
    'explicit connect recovers a dead connection on its first request',
    () async {
      await connect();
      backends[0].connected = false;
      expect((await connect()).exitCode, 0);
      expect(backends.length, 2);
      expect(manager.sessions['a']!.status, 'connected');
    },
  );
  test(
    'session list reports queue timeout instead of a false empty list',
    () async {
      await connect();
      final gate = Completer<void>();
      final entered = Completer<void>();
      backends[0].hooks['inspect'] = () {
        entered.complete();
        return gate.future;
      };
      final first = manager.handle(request('read'));
      await entered.future;
      final listing = await manager.handle(
        request('session', params: {'action': 'list'}, ms: 20),
      );
      expect(listing.error!.code, 'TIMEOUT');
      expect(listing.session, isNull);
      gate.complete();
      await first;
    },
  );
  test(
    'rejected new reservations do not outlive the last connected session',
    () async {
      await connect();
      expect((await connect('b')).error!.code, 'SESSION_CONFLICT');
      expect(
        (await connect('invalid', 'not-a-uri')).error!.code,
        'INVALID_ARGUMENT',
      );
      expect(manager.sessions.keys, ['a']);
      expect(backends.length, 1);
      await manager.handle(request('close'));
      expect(manager.sessions, isEmpty);
      expect(manager.stopping, isTrue);
    },
  );

  test(
    'rejected reservation preserves a queued connect on the same session',
    () async {
      await connect();
      final rejected = connect('b');
      final accepted = connect('b', 'http://localhost:2/');
      expect((await rejected).error!.code, 'SESSION_CONFLICT');
      expect((await accepted).exitCode, 0);
      expect(manager.sessions['b']!.status, 'connected');
      await manager.handle(request('close'));
      expect(manager.stopping, isFalse);
      expect((await manager.handle(request('read', session: 'b'))).exitCode, 0);
    },
  );

  test(
    'invalid connect does not destroy an existing session or its refs',
    () async {
      await connect();
      final observation = Object();
      manager.sessions['a']!.observation = observation;
      expect((await connect('a', 'not-a-uri')).error!.code, 'INVALID_ARGUMENT');
      expect(
        (await connect('a', 'http://localhost:2/')).error!.code,
        'SESSION_CONFLICT',
      );
      expect(manager.sessions['a']!.observation, same(observation));
      expect(manager.sessions['a']!.status, 'connected');
      expect(backends.single.calls, isNot(contains('disconnect')));
    },
  );
}
