import 'dart:async';

import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;
import 'workflow_model_test.dart' show doc;

void main() {
  final parser = CliParser();

  test('wait grammar normalizes defaults and accepts common timeout', () {
    expect(parser.parse(['wait', '--key', 'later']).params, {
      'key': 'later',
      'state': 'exists',
      'pollIntervalMs': 100,
    });
    final invocation = parser.parse([
      'wait',
      '--text',
      'Ready',
      '--state',
      'gone',
      '--poll-interval',
      '50',
      '--timeout',
      '750',
    ]);
    expect(invocation.timeoutMs, 750);
    expect(invocation.params, {
      'text': 'Ready',
      'state': 'gone',
      'pollIntervalMs': 50,
    });
    expect(parser.usage, contains('wait observes only'));
  });

  test('wait grammar rejects refs, coordinates, bad selectors and options', () {
    for (final arguments in [
      ['wait'],
      ['wait', '@e1'],
      ['wait', '--x', '1', '--y', '2'],
      ['wait', '--key', 'a', '--type', 'Text'],
      ['wait', '--key', 'a', '--state', 'visible'],
      ['wait', '--key', 'a', '--poll-interval', '49'],
      ['wait', '--key', 'a', '--poll-interval', '1001'],
      ['wait', '--key', 'a', '--poll-interval', '50.0'],
    ]) {
      expect(
        () => parser.parse(arguments),
        throwsA(isA<AgentError>()),
        reason: arguments.join(' '),
      );
    }
  });

  group('standalone wait', () {
    late SessionManager manager;
    late FakeBackend backend;

    setUp(() async {
      backend = FakeBackend()
        ..elements = [ElementInfo(key: 'base', type: 'Button')];
      manager = SessionManager(() => backend, coreCommands());
      await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
    });

    tearDown(() => manager.dispose());

    Future<Result> waitFor(
      String value, {
      String kind = 'key',
      String state = 'exists',
      int interval = 50,
      int ms = 500,
    }) => manager.handle(
      request(
        'wait',
        ms: ms,
        params: {kind: value, 'state': state, 'pollIntervalMs': interval},
      ),
    );

    test('polls 0 to 1 without a mutation or ref change', () async {
      final snapshot = await manager.handle(request('snapshot'));
      final ref =
          ((snapshot.data!['elements'] as List).single as Map)['ref'] as String;
      var polls = 0;
      backend.hooks['inspect'] = () async {
        if (++polls == 3) {
          backend.elements.add(ElementInfo(key: 'later', visible: true));
        }
      };

      final result = await waitFor('later');

      expect(result.data, {'state': 'exists', 'requiresSnapshot': true});
      expect(polls, 3);
      expect(
        backend.calls.where((call) => ['tap', 'fill', 'swipe'].contains(call)),
        isEmpty,
      );
      backend.hooks.clear();
      expect(
        (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
        0,
        reason: 'successful wait must preserve the previously published ref',
      );
    });

    test('polls 1 to 0 and hidden to visible', () async {
      backend.elements.add(ElementInfo(key: 'temporary', visible: true));
      var polls = 0;
      backend.hooks['inspect'] = () async {
        if (++polls == 2) {
          backend.elements.removeWhere((element) => element.key == 'temporary');
        }
      };
      expect((await waitFor('temporary', state: 'gone')).exitCode, 0);
      expect(polls, 2);

      backend.elements.add(ElementInfo(key: 'hidden', visible: false));
      polls = 0;
      backend.hooks['inspect'] = () async {
        if (++polls == 2) {
          backend.elements = [
            ...backend.elements.where((element) => element.key != 'hidden'),
            ElementInfo(key: 'hidden', visible: true),
          ];
        }
      };
      expect((await waitFor('hidden')).exitCode, 0);
      expect(polls, 2);
      expect(backend.calls, isNot(contains('tap')));
    });

    test(
      'daemon rejects malformed params before observation and keeps refs',
      () async {
        final snapshot = await manager.handle(request('snapshot'));
        final ref =
            ((snapshot.data!['elements'] as List).single as Map)['ref']
                as String;
        final observed = backend.calls
            .where((call) => call == 'inspect')
            .length;
        for (final params in <Json>[
          {'ref': ref},
          {'x': 1, 'y': 2},
          {'key': 'base', 'type': 'Button'},
          {'key': 'base', 'state': 'visible'},
          {'key': 'base', 'pollIntervalMs': 49},
          {'key': 'base', 'pollIntervalMs': 50.0},
          {'key': 'base', 'unknown': true},
        ]) {
          final result = await manager.handle(request('wait', params: params));
          expect(result.error!.code, 'INVALID_ARGUMENT', reason: '$params');
        }
        expect(
          backend.calls.where((call) => call == 'inspect').length,
          observed,
        );
        expect(
          (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
          0,
        );
      },
    );

    test(
      'unsupported selector is rejected before inspect and keeps refs',
      () async {
        final snapshot = await manager.handle(request('snapshot'));
        final ref =
            ((snapshot.data!['elements'] as List).single as Map)['ref']
                as String;
        final observed = backend.calls
            .where((call) => call == 'inspect')
            .length;

        final result = await waitFor('identifier', kind: 'identifier');

        expect(result.error!.code, 'UNSUPPORTED_CAPABILITY');
        expect(
          backend.calls.where((call) => call == 'inspect').length,
          observed,
        );
        expect(
          (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
          0,
        );
      },
    );

    test('condition timeout is not_sent and retires refs', () async {
      await manager.handle(request('snapshot'));

      final result = await waitFor('absent', ms: 70);

      expect(result.error!.code, 'TIMEOUT');
      expect(result.error!.outcome, Outcome.notSent);
      expect(manager.sessions['a']!.status, 'disconnected');
      expect(manager.sessions['a']!.observation, isNull);
      expect(backend.calls, isNot(contains('tap')));
    });

    test('read disconnect is not_sent and retires refs', () async {
      await manager.handle(request('snapshot'));
      backend.hooks['inspect'] = () async {
        throw const AgentError('CONNECTION_LOST', 'lost');
      };

      final result = await waitFor('base');

      expect(result.error!.code, 'CONNECTION_LOST');
      expect(result.error!.outcome, Outcome.notSent);
      expect(manager.sessions['a']!.status, 'disconnected');
      expect(manager.sessions['a']!.observation, isNull);
      expect(backend.calls, isNot(contains('tap')));
    });

    test('queue timeout never polls and preserves the connection', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      backend.hooks['inspect'] = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final blocking = manager.handle(request('snapshot'));
      await entered.future;
      final queued = await waitFor('base', ms: 20);
      expect(queued.error!.code, 'TIMEOUT');
      expect(queued.error!.outcome, Outcome.notSent);
      release.complete();
      await blocking;
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls.where((call) => call == 'inspect').length, 1);
      expect(manager.sessions['a']!.status, 'connected');
      expect(manager.sessions['a']!.observation, isNotNull);
    });
  });

  test(
    'standalone and workflow wait return matching condition outcomes',
    () async {
      final scenarios =
          <
            ({
              List<ElementInfo> elements,
              String kind,
              String value,
              String state,
            })
          >[
            (
              elements: [ElementInfo(key: 'target', visible: true)],
              kind: 'key',
              value: 'target',
              state: 'exists',
            ),
            (
              elements: [ElementInfo(key: 'target', visible: null)],
              kind: 'key',
              value: 'target',
              state: 'exists',
            ),
            (
              elements: [
                ElementInfo(key: 'target', visible: true),
                ElementInfo(key: 'target', visible: false),
              ],
              kind: 'key',
              value: 'target',
              state: 'exists',
            ),
            (
              elements: [ElementInfo(text: 'Ready', textMatchable: false)],
              kind: 'text',
              value: 'Ready',
              state: 'exists',
            ),
            (
              elements: [
                ElementInfo(text: 'Ready', textMatchable: true),
                ElementInfo(text: 'Ready', textMatchable: false),
              ],
              kind: 'text',
              value: 'Ready',
              state: 'exists',
            ),
            (elements: const [], kind: 'key', value: 'target', state: 'gone'),
            (
              elements: [ElementInfo(text: 'Ready', textMatchable: false)],
              kind: 'text',
              value: 'Ready',
              state: 'gone',
            ),
            (
              elements: [ElementInfo(key: 'target', visible: false)],
              kind: 'key',
              value: 'target',
              state: 'exists',
            ),
            (
              elements: [ElementInfo(key: 'target')],
              kind: 'key',
              value: 'target',
              state: 'gone',
            ),
          ];

      Future<Result> runScenario(
        ({List<ElementInfo> elements, String kind, String value, String state})
        scenario, {
        required bool workflow,
      }) async {
        final backend = FakeBackend()..elements = List.of(scenario.elements);
        final manager = SessionManager(() => backend, coreCommands());
        try {
          await manager.handle(
            request('connect', params: {'uri': 'http://localhost:1/'}),
          );
          if (!workflow) {
            return await manager.handle(
              request(
                'wait',
                ms: 90,
                params: {
                  scenario.kind: scenario.value,
                  'state': scenario.state,
                  'pollIntervalMs': 50,
                },
              ),
            );
          }
          return await manager.handle(
            request(
              'workflow',
              ms: 300,
              params: {
                'workflow': doc([
                  {
                    'id': 'condition',
                    'action': 'wait',
                    'target': {scenario.kind: scenario.value},
                    'state': scenario.state,
                    'timeoutMs': 90,
                    'pollIntervalMs': 50,
                  },
                ]),
                'inputs': <String, Object?>{},
              },
            ),
          );
        } finally {
          await manager.dispose();
        }
      }

      for (final scenario in scenarios) {
        final standalone = await runScenario(scenario, workflow: false);
        final workflow = await runScenario(scenario, workflow: true);
        expect(
          workflow.error?.code,
          standalone.error?.code,
          reason: '$scenario',
        );
        expect(
          workflow.error?.outcome,
          standalone.error?.outcome,
          reason: '$scenario',
        );
        expect(workflow.exitCode == 0, standalone.exitCode == 0);
      }
    },
  );
}
