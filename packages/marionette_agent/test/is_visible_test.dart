import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

void main() {
  test('grammar accepts one target and rejects malformed requests', () {
    final parser = CliParser();
    expect(parser.parse(['is', 'visible', '@e1']).params, {
      'action': 'visible',
      'ref': '@e1',
    });
    expect(parser.parse(['is', 'visible', '--key', 'a']).params, {
      'action': 'visible',
      'key': 'a',
    });
    expect(parser.usage, contains('is visible'));
    for (final args in [
      ['is'],
      ['is', 'enabled', '@e1'],
      ['is', 'visible'],
      ['is', 'visible', '@e1', 'extra'],
      ['is', 'visible', '@e1', '--key', 'a'],
      ['is', 'visible', '--key', ''],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });

  group('read-only visibility', () {
    late FakeBackend backend;
    late SessionManager manager;
    setUp(() async {
      backend = FakeBackend();
      manager = SessionManager(() => backend, coreCommands());
      await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
    });
    tearDown(() => manager.dispose());
    Future<Result> visible(Json target) =>
        manager.handle(request('is', params: {'action': 'visible', ...target}));

    test(
      'true false null stay distinct without mutations or new refs',
      () async {
        for (final value in <bool?>[true, false, null]) {
          backend.elements = [ElementInfo(key: 'a', visible: value)];
          final result = await visible({'key': 'a'});
          expect(result.data, {'known': value != null, 'value': value});
          expect(render(result, json: false), 'Visible: ${value ?? 'unknown'}');
          expect(manager.sessions['a']!.observation, isNull);
        }
        expect(
          backend.calls.where((c) => ['tap', 'fill', 'swipe'].contains(c)),
          isEmpty,
        );
      },
    );

    test('success preserves the exact published observation and ref', () async {
      backend.elements = [ElementInfo(key: 'a')];
      final snapshot = await manager.handle(request('snapshot'));
      final ref = (snapshot.data!['elements'] as List).single['ref'];
      final observation = manager.sessions['a']!.observation;
      expect((await visible({'ref': ref})).data, {
        'known': false,
        'value': null,
      });
      expect(
        identical(manager.sessions['a']!.observation, observation),
        isTrue,
      );
      expect(
        (await manager.handle(request('tap', params: {'ref': ref}))).exitCode,
        0,
      );
    });

    test('missing ambiguous unsupported and stale are errors', () async {
      expect(
        (await visible({'key': 'absent'})).error!.code,
        'TARGET_NOT_FOUND',
      );
      backend.elements = [ElementInfo(key: 'a'), ElementInfo(key: 'a')];
      expect((await visible({'key': 'a'})).error!.code, 'AMBIGUOUS_TARGET');
      final calls = backend.calls.length;
      expect(
        (await visible({'identifier': 'a'})).error!.code,
        'UNSUPPORTED_CAPABILITY',
      );
      expect(backend.calls.length, calls);
      backend.elements = [ElementInfo(key: 'a', visible: true)];
      final snapshot = await manager.handle(request('snapshot'));
      final ref = (snapshot.data!['elements'] as List).single['ref'];
      backend.elements = [ElementInfo(key: 'a', visible: false)];
      expect((await visible({'ref': ref})).error!.code, 'STALE_REF');
      expect((await visible({'ref': '@e999'})).error!.code, 'STALE_REF');
      expect(
        (await visible({'key': 'a', 'unexpected': true})).error!.code,
        'INVALID_ARGUMENT',
      );
      expect(backend.calls, isNot(contains('tap')));
    });
  });
}
