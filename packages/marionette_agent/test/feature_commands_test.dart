import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

class RecordingBackend extends FakeBackend {
  TapTarget? tapped;
  String? input;
  SwipeGesture? gesture;
  @override
  Future<void> tap(TapTarget target) {
    tapped = target;
    return super.tap(target);
  }

  @override
  Future<void> fill(Selector selector, String text) {
    input = text;
    return super.fill(selector, text);
  }

  @override
  Future<void> swipe(SwipeGesture value) {
    gesture = value;
    return super.swipe(value);
  }
}

void main() {
  final parser = CliParser();
  test('tap/fill/scroll grammar accepts modes and opaque empty input', () {
    expect(parser.parse(['tap', '@e1']).params, {'ref': '@e1'});
    expect(parser.parse(['tap', '--x', '0', '--y', '12.5']).params, {
      'x': '0',
      'y': '12.5',
    });
    expect(parser.parse(['fill', '--key', 'input', '']).params, {
      'key': 'input',
      'input': '',
    });
    expect(
      parser.parse(['fill', '@e1', '--', '--json']).params['input'],
      '--json',
    );
    expect(parser.parse(['fill', '--text', 'Label', 'secret']).params, {
      'text': 'Label',
      'input': 'secret',
    });
    expect(parser.parse(['scroll', '--key', 'list', 'up']).command, 'scroll');
    expect(parser.usage, contains('reaching content is not guaranteed'));
    expect(
      () => parser.parse(['scroll']),
      throwsA(
        isA<AgentError>().having(
          (e) => e.message,
          'usage',
          startsWith('Usage: scroll'),
        ),
      ),
    );
    expect(parser.parse(['screenshot', 'a.png']).params, {'path': 'a.png'});
    expect(parser.parse(['logs']).params, isEmpty);
  });
  test('bad arguments are rejected before IPC without exposing input', () {
    for (final args in [
      ['tap'],
      ['tap', '@e1', '--key', 'a'],
      ['tap', '--x', '1'],
      ['tap', '--x', 'NaN', '--y', '0'],
      ['tap', '--x', '-1', '--y', '0'],
      ['tap', '--x', '1', '--y', '2', '@e1'],
      ['tap', '--key', 'a', '--type', 'Text'],
      ['fill', '@e1'],
      ['fill', '--key', 'a', 'x', 'y'],
      ['fill', '@e1', '--x', '1', 'secret'],
      ['scroll', '--start-x', '1'],
      ['logs', 'extra'],
      ['screenshot', ''],
      ['screenshot', 'a', 'b'],
    ]) {
      expect(
        () => parser.parse(args),
        throwsA(isA<AgentError>()),
        reason: args.first,
      );
    }
  });
  late SessionManager manager;
  late RecordingBackend backend;
  setUp(() async {
    backend = RecordingBackend()
      ..elements = [ElementInfo(key: 'input', type: 'TextField')];
    manager = SessionManager(() => backend, coreCommands());
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
  });
  tearDown(() => manager.dispose());
  Future<String> ref() async =>
      (((await manager.handle(request('snapshot'))).data!['elements'] as List)
                  .single
              as Map)['ref']
          as String;
  Future<Result> call(String command, Json params) =>
      manager.handle(request(command, params: params));
  test('tap by ref and coordinates dispatch once and invalidate', () async {
    final target = await ref();
    expect((await call('tap', {'ref': target})).data, {
      'requiresSnapshot': true,
    });
    expect((backend.tapped as ElementTarget).selector.value, 'input');
    expect((await call('tap', {'ref': target})).exitCode, 4);
    expect((await call('tap', {'x': 10, 'y': 20})).exitCode, 0);
    expect((backend.tapped as CoordinateTarget).point.y, 20);
    expect(backend.calls.where((c) => c == 'tap').length, 2);
  });
  test(
    'fill replaces, clears and does not record input in diagnostics/calls',
    () async {
      for (final input in ['sensitive-test-input', '']) {
        final target = await ref();
        final result = await call('fill', {'ref': target, 'input': input});
        expect(result.data, {'requiresSnapshot': true});
        expect(backend.input, input);
        expect(
          (await call('fill', {'ref': target, 'input': 'again'})).error!.code,
          'STALE_REF',
        );
      }
      expect(backend.calls.join(), isNot(contains('sensitive-test-input')));
    },
  );
  test('non-input backend rejection is failed and invalidates refs', () async {
    final target = await ref();
    backend.hooks['fill'] = () async {
      throw const AgentError(
        'BACKEND_ERROR',
        'Not an input',
        outcome: Outcome.failed,
      );
    };
    expect(
      (await call('fill', {'ref': target, 'input': 'secret'})).error!.outcome,
      Outcome.failed,
    );
    expect((await call('tap', {'ref': target})).error!.code, 'STALE_REF');
  });
  test(
    'malformed IPC preserves refs; ambiguity and disconnected sessions reject',
    () async {
      final target = await ref();
      for (final params in <Json>[
        {'ref': target, 'x': 1, 'y': 2},
        {'ref': target, 'unknown': 1},
        {'key': false},
      ]) {
        expect((await call('tap', params)).exitCode, 2);
      }
      expect((await call('fill', {'ref': target, 'input': 42})).exitCode, 2);
      expect((await call('tap', {'ref': target})).exitCode, 0);
      backend.elements.add(ElementInfo(key: 'input', type: 'TextField'));
      expect(
        (await call('tap', {'key': 'input'})).error!.code,
        'AMBIGUOUS_TARGET',
      );
      expect(
        (await manager.handle(
          request('tap', session: 'missing', params: {'key': 'input'}),
        )).exitCode,
        3,
      );
    },
  );
  test(
    'scroll uses swipe primitive with direction and forbids coordinates',
    () async {
      final target = await ref();
      expect(
        (await call('scroll', {
          'ref': target,
          'direction': 'up',
          'distance': 75,
        })).data,
        {'requiresSnapshot': true, 'command': 'scroll'},
      );
      expect((backend.gesture as ElementSwipe).direction, Direction.up);
      expect((backend.gesture as ElementSwipe).distance, 75);
      expect(
        (await call('scroll', {
          'start-x': 0,
          'start-y': 0,
          'end-x': 0,
          'end-y': 1,
        })).exitCode,
        2,
      );
    },
  );
  test('read commands preserve refs, log configuration and failures', () async {
    final target = await ref();
    backend.screenshots = ['encoded'];
    expect((await call('screenshot', {})).data, {
      'images': ['encoded'],
    });
    expect((await call('logs', {})).data, {'entries': [], 'configured': true});
    backend.logs = const LogBatch([], configured: false);
    expect((await call('logs', {})).data!['configured'], false);
    backend.logs = const LogBatch([]);
    expect((await call('logs', {})).data!['limitation'], isA<String>());
    backend.logs = const LogBatch(['entry'], configured: true);
    expect((await call('logs', {})).data!['entries'], ['entry']);
    backend.hooks['readLogs'] = () async {
      throw const AgentError(
        'BACKEND_ERROR',
        'Rejected',
        outcome: Outcome.failed,
      );
    };
    expect((await call('logs', {})).exitCode, 1);
    expect((await call('tap', {'ref': target})).exitCode, 0);
  });
}
