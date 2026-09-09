import 'dart:async';

import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

class GestureBackend extends FakeBackend {
  SwipeGesture? gesture;
  @override
  Future<void> swipe(SwipeGesture value) {
    gesture = value;
    return super.swipe(value);
  }
}

void main() {
  final parser = CliParser();
  test('grammar accepts both modes, selectors and common options', () {
    expect(parser.parse(['swipe', '@e1', 'left', '--json']).params, {
      'ref': '@e1',
      'direction': 'left',
    });
    expect(
      parser.parse([
        'swipe',
        '--key',
        'pager',
        'up',
        '--distance',
        '50',
      ]).params['distance'],
      '50',
    );
    expect(
      parser.parse([
        'swipe',
        '--start-x',
        '0',
        '--start-y',
        '0',
        '--end-x',
        '100',
        '--end-y',
        '0',
      ]).command,
      'swipe',
    );
  });
  test('invalid grammar, nonfinite numbers and mixed modes are rejected', () {
    for (final args in [
      <String>[],
      ['@e1'],
      ['@e1', 'north'],
      ['@e1', 'left', '--distance', '0'],
      ['@e1', 'left', '--distance', 'NaN'],
      ['@e1', 'left', '--distance', 'Infinity'],
      ['@e1', '--key', 'pager', 'left'],
      ['--key', 'a', '--text', 'b', 'up'],
      ['--start-x', '0'],
      ['--start-x', '0', '--start-y', '0', '--end-x', '0', '--end-y', '0'],
      ['--start-x', '-1', '--start-y', '0', '--end-x', '100', '--end-y', '0'],
      [
        '--start-x',
        '0',
        '--start-y',
        '0',
        '--end-x',
        '100',
        '--end-y',
        '0',
        '--distance',
        '50',
      ],
      ['@e1', 'left', '--distance', '20', '--distance', '30'],
    ]) {
      expect(
        () => parser.parse(['swipe', ...args]),
        throwsA(isA<AgentError>()),
        reason: args.toString(),
      );
    }
  });

  late SessionManager manager;
  late GestureBackend backend;
  setUp(() async {
    backend = GestureBackend()
      ..elements = [ElementInfo(key: 'pager', type: 'PageView')];
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
  Future<Result> swipe(Json params) =>
      manager.handle(request('swipe', params: params));
  test('element gesture maps values once and invalidates refs', () async {
    final target = await ref();
    final result = await swipe({
      'ref': target,
      'direction': 'right',
      'distance': 123,
    });
    expect(result.data, {'requiresSnapshot': true});
    final gesture = backend.gesture as ElementSwipe;
    expect(gesture.selector.value, 'pager');
    expect(gesture.direction, Direction.right);
    expect(gesture.distance, 123);
    expect(
      (await swipe({'ref': target, 'direction': 'left'})).error!.code,
      'STALE_REF',
    );
    expect(backend.calls.where((c) => c == 'swipe').length, 1);
  });
  test('coordinate gesture dispatches once with no pre-observation', () async {
    final target = await ref();
    backend.calls.clear();
    expect(
      (await swipe({'start-x': 1, 'start-y': 2, 'end-x': 3, 'end-y': 4}))
          .exitCode,
      0,
    );
    expect(backend.calls, ['swipe']);
    final gesture = backend.gesture as CoordinateSwipe;
    expect(
      [gesture.start.x, gesture.start.y, gesture.end.x, gesture.end.y],
      [1, 2, 3, 4],
    );
    expect((await swipe({'ref': target, 'direction': 'up'})).exitCode, 4);
  });
  test('invalid IPC preserves refs, ambiguous targets do not send', () async {
    final target = await ref();
    for (final params in <Json>[
      {'ref': target, 'direction': 'up', 'distance': -1},
      {'ref': target, 'direction': 'up', 'unknown': true},
      {'ref': target, 'direction': 'up', 'key': 'pager'},
      {'start-x': 0, 'start-y': 0, 'end-x': 0, 'end-y': 0},
      {'key': 42, 'direction': 'left'},
    ]) {
      expect((await swipe(params)).exitCode, 2);
    }
    expect((await swipe({'ref': target, 'direction': 'down'})).exitCode, 0);
    backend.elements.add(ElementInfo(key: 'pager', type: 'PageView'));
    expect(
      (await swipe({'key': 'pager', 'direction': 'left'})).error!.code,
      'AMBIGUOUS_TARGET',
    );
    expect(backend.calls.where((c) => c == 'swipe').length, 1);
  });
  test('definite backend failure invalidates refs without resending', () async {
    final target = await ref();
    backend.hooks['swipe'] = () async {
      throw const AgentError(
        'BACKEND_ERROR',
        'Rejected',
        outcome: Outcome.failed,
      );
    };
    expect(
      (await swipe({'ref': target, 'direction': 'up'})).error!.outcome,
      Outcome.failed,
    );
    expect(
      (await swipe({'ref': target, 'direction': 'up'})).error!.code,
      'STALE_REF',
    );
    expect(backend.calls.where((c) => c == 'swipe').length, 1);
  });
  test(
    'post-send timeout is unknown, disconnected and never retried',
    () async {
      final gate = Completer<void>();
      backend.hooks['swipe'] = () => gate.future;
      final result = await manager.handle(
        request('swipe', params: {'key': 'pager', 'direction': 'left'}, ms: 30),
      );
      expect(result.exitCode, 5);
      expect(result.error!.outcome, Outcome.unknown);
      expect(manager.sessions['a']!.status, 'disconnected');
      expect(backend.calls.where((c) => c == 'swipe').length, 1);
      gate.complete();
    },
  );
}
