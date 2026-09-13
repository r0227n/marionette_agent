import 'dart:async';

import 'package:args/args.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/cli/target_options.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/snapshot/target.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

ElementInfo button({
  String key = 'save',
  String text = 'Save',
  double x = 0,
  bool visible = true,
}) => ElementInfo(
  type: 'Button',
  key: key,
  text: text,
  textMatchable: true,
  visible: visible,
  bounds: {'x': x, 'y': 0.0, 'width': 100.0, 'height': 40.0},
);
void main() {
  late SessionManager manager;
  late List<FakeBackend> backends;
  setUp(() async {
    backends = [];
    final registry = coreCommands();
    registry.register('act', (context, params) {
      if (params['invalid'] == true) invalid();
      final query = params['ref'] is String
          ? RefQuery(params['ref'] as String)
          : SelectorQuery(
              Selector(
                SelectorKind.values.byName(params['kind'] as String),
                params['value'] as String,
              ),
            );
      return context.performTarget(
        query,
        (backend, selector) => backend.tap(ElementTarget(selector)),
      );
    });
    registry.register(
      'read',
      (context, params) => context.read((backend) async {
        await backend.readLogs();
        return {};
      }),
    );
    manager = SessionManager(() {
      final backend = FakeBackend()..elements = [button()];
      backends.add(backend);
      return backend;
    }, registry);
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
  });
  tearDown(() async {
    await manager.dispose();
  });
  Future<Result> snapshot([String name = 'a']) =>
      manager.handle(request('snapshot', session: name));
  Future<String> ref([String name = 'a']) async =>
      (((await snapshot(name)).data!['elements'] as List).first as Map)['ref']
          as String;
  Future<Result> act(String ref) =>
      manager.handle(request('act', params: {'ref': ref}));
  test(
    'new observations invalidate old refs and never reuse across sessions',
    () async {
      final first = await ref();
      final second = await ref();
      expect((await act(first)).error!.code, 'STALE_REF');
      expect(second, isNot(first));
      await manager.handle(
        request(
          'connect',
          session: 'b',
          params: {'uri': 'http://localhost:2/'},
        ),
      );
      final other = await ref('b');
      expect(other, isNot(second));
      expect(
        (await manager.handle(
          request('act', session: 'b', params: {'ref': second}),
        )).error!.code,
        'STALE_REF',
      );
      expect((await act(second)).exitCode, 0);
      expect(
        (await manager.handle(
          request('act', session: 'b', params: {'ref': other}),
        )).exitCode,
        0,
      );
    },
  );
  test('sent action invalidates all refs, even on definite failure', () async {
    final target = await ref();
    backends[0].hooks['tap'] = () async {
      throw const AgentError(
        'BACKEND_ERROR',
        'rejected',
        outcome: Outcome.failed,
      );
    };
    final result = await act(target);
    expect(result.error!.outcome, Outcome.failed);
    expect((await act(target)).error!.code, 'STALE_REF');
    expect(backends[0].calls.where((c) => c == 'tap').length, 1);
  });
  test('argument-only failure and read do not invalidate refs', () async {
    final target = await ref();
    expect(
      (await manager.handle(request('act', params: {'invalid': true})))
          .exitCode,
      2,
    );
    await manager.handle(request('read'));
    expect((await act(target)).data, {'requiresSnapshot': true});
  });
  test(
    'preflight detects text, bounds and identity changes without sending',
    () async {
      for (final changed in [
        button(text: 'Changed'),
        button(x: 1),
        button(key: 'other'),
        button(visible: false),
      ]) {
        backends[0].elements = [button()];
        final target = await ref();
        backends[0].elements = [changed];
        expect((await act(target)).error!.code, 'STALE_REF');
      }
      expect(backends[0].calls, isNot(contains('tap')));
    },
  );
  test(
    'duplicate targets are rejected for refs and explicit selectors',
    () async {
      final target = await ref();
      backends[0].elements = [button(), button()];
      expect((await act(target)).error!.code, 'AMBIGUOUS_TARGET');
      final result = await manager.handle(
        request('act', params: {'kind': 'key', 'value': 'save'}),
      );
      expect(result.error!.code, 'AMBIGUOUS_TARGET');
      final rows = (await snapshot()).data!['elements'] as List;
      expect(rows.every((row) => !(row as Map).containsKey('ref')), true);
      expect(backends[0].calls, isNot(contains('tap')));
    },
  );
  test(
    'Semantics discovery text is not a text selector; hidden duplicates count',
    () async {
      backends[0].elements = [
        ElementInfo(type: 'Semantics', text: 'Save', visible: true),
        ElementInfo(type: 'Semantics', text: 'Volume: 70%', visible: true),
        button(visible: false),
        button(),
      ];
      final rows = (await snapshot()).data!['elements'] as List;
      expect((rows[0] as Map)['text'], 'Save');
      expect((rows[0] as Map).containsKey('ref'), false);
      expect((rows[2] as Map)['reason'], 'not_visible');
      expect(
        (await manager.handle(
          request('act', params: {'kind': 'key', 'value': 'save'}),
        )).error!.code,
        'AMBIGUOUS_TARGET',
      );
      expect(
        (await manager.handle(
          request('act', params: {'kind': 'text', 'value': 'Volume: 70%'}),
        )).error!.code,
        'UNRESOLVABLE_TARGET',
      );
      expect(
        (await manager.handle(
          request('act', params: {'kind': 'identifier', 'value': 'missing'}),
        )).error!.code,
        'UNSUPPORTED_CAPABILITY',
      );
    },
  );
  test(
    'late snapshot cannot repopulate state after timeout and reconnect',
    () async {
      final gate = Completer<void>();
      backends[0].hooks['inspect'] = () => gate.future;
      final result = await manager.handle(request('snapshot', ms: 25));
      expect(result.error!.code, 'TIMEOUT');
      await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(manager.sessions['a']!.observation, isNull);
      expect(manager.sessions['a']!.status, 'connected');
    },
  );
  test('selector args use ArgParser and reject mixed target modes', () {
    final parser = ArgParser();
    addSelectorOptions(parser);
    expect(parseTarget(parser.parse(['--key', 'save'])), isA<SelectorQuery>());
    expect(
      () => parseTarget(parser.parse(['--key', 'save']), ref: '@e1'),
      throwsA(isA<AgentError>()),
    );
    expect(
      () => parseTarget(parser.parse(['--key', 'save', '--type', 'Button'])),
      throwsA(isA<AgentError>()),
    );
    expect(() => RefQuery('@e0'), throwsA(isA<AgentError>()));
  });
}
