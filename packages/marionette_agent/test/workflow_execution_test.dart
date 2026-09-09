import 'dart:async';
import 'dart:convert';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;
import 'workflow_model_test.dart' show doc;

Json tap(String id, [String key = 'button']) => {
  'id': id,
  'action': 'tap',
  'target': {'key': key},
};
Json snap(String id) => {'id': id, 'action': 'snapshot'};
Json wait(
  String id, {
  String key = 'button',
  String state = 'exists',
  int ms = 200,
}) => {
  'id': id,
  'action': 'wait',
  'target': {'key': key},
  'state': state,
  'timeoutMs': ms,
  'pollIntervalMs': 50,
};
void main() {
  late SessionManager manager;
  late List<FakeBackend> backends;
  setUp(() {
    backends = [];
    manager = SessionManager(() {
      final b = FakeBackend()
        ..elements = [
          ElementInfo(key: 'button', type: 'Button'),
          ElementInfo(key: 'field', type: 'TextField'),
        ];
      backends.add(b);
      return b;
    }, coreCommands());
  });
  tearDown(() => manager.dispose());
  Future<Result> connect([String name = 'a']) => manager.handle(
    request(
      'connect',
      session: name,
      params: {'uri': 'http://localhost:1/$name/'},
    ),
  );
  Future<Result> run(List<Json> steps, {int ms = 2000, String session = 'a'}) =>
      manager.handle(
        request(
          'workflow',
          session: session,
          ms: ms,
          params: {'workflow': doc(steps), 'inputs': <String, Object?>{}},
        ),
      );
  test('three mutations dispatch once each and final ref continues in a new request', () async {
    await connect();
    final b = backends.single;
    final r = await run([
      tap('tap'),
      {
        'id': 'fill',
        'action': 'fill',
        'target': {'key': 'field'},
        'text': {'literal': 'private'},
      },
      {
        'id': 'swipe',
        'action': 'swipe',
        'target': {'key': 'button'},
        'direction': 'left',
      },
      snap('last'),
    ]);
    expect(r.error, isNull);
    expect(r.data!['completedSteps'], 4);
    expect(r.data!['requiresSnapshot'], false);
    expect(b.calls.where((v) => ['tap', 'fill', 'swipe'].contains(v)), [
      'tap',
      'fill',
      'swipe',
    ]);
    expect(jsonEncode(r.toJson()), isNot(contains('private')));
    final ref =
        ((r.data!['finalSnapshot'] as Map)['elements'] as List).first['ref'];
    expect(
      (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
      0,
    );
  });
  test('completed child cannot send while parent proceeds', () async {
    await connect();
    final child = Execution(request('tap'), manager.sessions['a']!);
    await child.bound(() async => <String, Object?>{});
    await expectLater(
      child.mutate((b) => b.tap(CoordinateTarget(Point(1, 1)))),
      throwsA(isA<AgentError>()),
    );
    expect(backends.single.calls, isNot(contains('tap')));
  });
  test('single Execution still forbids two UI dispatches', () async {
    await connect();
    final execution = Execution(request('tap'), manager.sessions['a']!);
    await execution.mutate((b) => b.tap(CoordinateTarget(Point(1, 1))));
    await expectLater(
      execution.mutate((b) => b.tap(CoordinateTarget(Point(1, 1)))),
      throwsA(
        isA<AgentError>().having((e) => e.code, 'code', 'INTERNAL_ERROR'),
      ),
    );
    expect(backends.single.calls.where((s) => s == 'tap').length, 1);
  });
  test(
    'second target failure stops third step and keeps step not_sent',
    () async {
      await connect();
      final r = await run([
        tap('first'),
        tap('missing', 'absent'),
        tap('never'),
      ]);
      expect(r.error!.code, 'TARGET_NOT_FOUND');
      expect(r.error!.outcome, Outcome.notSent);
      expect(r.error!.details, {
        'workflow': 'example',
        'progressKnown': true,
        'stepIndex': 2,
        'stepId': 'missing',
        'action': 'tap',
        'completedSteps': 1,
      });
      expect(backends.single.calls.where((s) => s == 'tap').length, 1);
      expect(manager.sessions['a']!.status, 'connected');
      expect(r.data, isNull);
    },
  );
  test(
    'confirmed failure preserves failed and scrubs backend message',
    () async {
      await connect();
      backends.single.hooks['tap'] = () async => throw const AgentError(
        'BACKEND_ERROR',
        'secret-selector private-value',
      );
      final r = await run([tap('first'), tap('never')]);
      expect(r.error!.outcome, Outcome.failed);
      expect(jsonEncode(r.toJson()), isNot(contains('private-value')));
      expect(manager.sessions['a']!.status, 'connected');
    },
  );
  test(
    'whole plan validation and capabilities precede first mutation',
    () async {
      await connect();
      for (final last in [
        {
          'id': 'invalid',
          'action': 'fill',
          'target': {'key': 'field'},
        },
        {
          'id': 'unsupported',
          'action': 'tap',
          'target': {'identifier': 'id'},
        },
      ]) {
        final r = await run([tap('first'), last]);
        expect(r.error, isNotNull);
        expect(r.error!.details!['completedSteps'], 0);
        expect(r.error!.details!['stepIndex'], isNull);
      }
      expect(backends.single.calls, ['connect']);
    },
  );
  test(
    'same session is atomic, another session progresses while step is pending',
    () async {
      await connect();
      await connect('b');
      final entered = Completer<void>();
      final release = Completer<void>();
      var taps = 0;
      backends.first.hooks['tap'] = () async {
        if (++taps == 1) {
          entered.complete();
          await release.future;
        }
      };
      final flow = run([tap('one'), tap('two')]);
      await entered.future;
      final queued = manager.handle(request('tap', params: {'key': 'button'}));
      expect(
        (await manager.handle(
          request('tap', session: 'b', params: {'key': 'button'}),
        )).exitCode,
        0,
      );
      expect(taps, 1);
      release.complete();
      expect((await flow).data!['completedSteps'], 2);
      expect((await queued).exitCode, 0);
      expect(taps, 3);
    },
  );
  test('queued workflow expires without changing refs or executing', () async {
    await connect();
    await manager.handle(request('snapshot'));
    final observation = manager.sessions['a']!.observation;
    final release = Completer<void>();
    final started = Completer<void>();
    backends.single.hooks['inspect'] = () async {
      started.complete();
      await release.future;
    };
    final blocking = manager.handle(request('snapshot'));
    await started.future;
    final r = await run([tap('never')], ms: 20);
    expect(r.error!.outcome, Outcome.notSent);
    expect(r.error!.details!['stepIndex'], isNull);
    release.complete();
    await blocking;
    await Future<void>.delayed(Duration.zero);
    expect(backends.single.calls, isNot(contains('tap')));
    expect(manager.sessions['a']!.status, 'connected');
    expect(observation, isNotNull);
  });
  test('wait polls inspect without publishing refs; snapshot then wait remains valid', () async {
    await connect();
    int count = 0;
    backends.single.hooks['inspect'] = () async {
      if (++count == 3) backends.single.elements.add(ElementInfo(key: 'later'));
    };
    final r = await run([snap('before'), wait('wait', key: 'later', ms: 500)]);
    expect(r.exitCode, 0);
    expect(count, 3);
    expect(r.data!['requiresSnapshot'], false);
    expect(
      backends.single.calls
          .where((s) => s != 'connect')
          .every((s) => s == 'inspect'),
      true,
    );
    final ref =
        ((r.data!['finalSnapshot'] as Map)['elements'] as List).first['ref'];
    backends.single.hooks.clear();
    expect(
      (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
      0,
    );
  });
  test(
    'wait counts hidden duplicates and distinguishes unmatched display text',
    () async {
      await connect();
      final b = backends.single;
      b.elements = [
        ElementInfo(key: 'button', visible: true),
        ElementInfo(key: 'button', visible: false),
      ];
      expect((await run([wait('ambiguous')])).error!.code, 'AMBIGUOUS_TARGET');
      b.elements = [ElementInfo(text: 'label', textMatchable: false)];
      expect(
        (await run([
          {
            'id': 'text',
            'action': 'wait',
            'target': {'text': 'label'},
            'state': 'gone',
          },
        ])).error!.code,
        'UNRESOLVABLE_TARGET',
      );
      expect((await run([wait('gone', state: 'gone')])).exitCode, 0);
    },
  );
  test(
    'tap then wait timeout is not_sent, retires refs, never sends next step',
    () async {
      await connect();
      final r = await run([
        tap('sent'),
        wait('timeout', key: 'absent', ms: 60),
        tap('never'),
      ]);
      expect(r.error!.code, 'TIMEOUT');
      expect(r.error!.outcome, Outcome.notSent);
      expect(r.error!.details!['completedSteps'], 1);
      expect(manager.sessions['a']!.status, 'disconnected');
      expect(manager.sessions['a']!.observation, isNull);
      expect(backends.single.calls.where((s) => s == 'tap').length, 1);
    },
  );
  for (final fail in ['timeout', 'disconnect', 'unclassified']) {
    test(
      'second mutation $fail is unknown; delayed completion cannot affect reconnect',
      () async {
        await connect();
        final old = backends.single;
        final release = Completer<void>();
        int count = 0;
        old.hooks['tap'] = () async {
          if (++count == 2) {
            if (fail == 'disconnect') {
              throw const AgentError('CONNECTION_LOST', 'secret');
            }
            if (fail == 'unclassified') throw StateError('secret');
            await release.future;
          }
        };
        final r = await run([
          tap('first'),
          tap('second'),
          tap('never'),
        ], ms: 80);
        expect(r.error!.outcome, Outcome.unknown);
        expect(r.error!.details!['completedSteps'], 1);
        await connect();
        final snapshot = await manager.handle(request('snapshot'));
        final observation = manager.sessions['a']!.observation;
        if (!release.isCompleted) release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(count, 2);
        expect(manager.sessions['a']!.status, 'connected');
        expect(
          identical(manager.sessions['a']!.observation, observation),
          true,
        );
        expect(snapshot.exitCode, 0);
      },
    );
  }
  test(
    'read timeout late snapshot cannot publish or dispatch after reconnect',
    () async {
      await connect();
      final old = backends.single;
      final release = Completer<void>();
      old.hooks['inspect'] = () => release.future;
      final r = await run([snap('late'), tap('never')], ms: 30);
      expect(r.error!.outcome, Outcome.notSent);
      await connect();
      await manager.handle(request('snapshot'));
      final observation = manager.sessions['a']!.observation;
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(old.calls, isNot(contains('tap')));
      expect(identical(manager.sessions['a']!.observation, observation), true);
    },
  );
  test('intermediate snapshot discarded and competing snapshot makes returned refs stale', () async {
    await connect();
    final r = await run([snap('before'), tap('mutate')]);
    expect(r.data!['requiresSnapshot'], true);
    expect(r.data!.containsKey('finalSnapshot'), false);
    final next = await run([snap('final')]);
    final ref =
        ((next.data!['finalSnapshot'] as Map)['elements'] as List).first['ref'];
    await manager.handle(request('snapshot'));
    expect(
      (await manager.handle(request('tap', params: {'ref': ref}))).error!.code,
      'STALE_REF',
    );
  });
  test('observed input may appear in final snapshot while arguments are not echoed', () async {
    await connect();
    backends.single.hooks['fill'] = () async {
      backends.single.elements = [ElementInfo(key: 'field', text: 'private')];
    };
    final r = await run([
      {
        'id': 'fill',
        'action': 'fill',
        'target': {'key': 'field'},
        'text': {'literal': 'private'},
      },
      snap('observe'),
    ]);
    expect(jsonEncode(r.toJson()), contains('private'));
    expect(r.data!.containsKey('inputs'), false);
  });
}
