import 'dart:async';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/platform/native/native_service.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/native_backend.dart';
import 'support/requests.dart';

void main() {
  late FakeBackend flutter;
  late FakeNativeBackend native;
  late SessionManager manager;
  Future<Result> call(String command, [Json params = const {}]) =>
      manager.handle(request(command, params: params));
  Future<String> ref(String source) async {
    final result = await call('snapshot');
    expect(result.error, isNull);
    return (result.data!['elements'] as List).firstWhere(
          (e) => e['source'] == source,
        )['ref']
        as String;
  }

  setUp(() async {
    flutter = FakeBackend()
      ..elements = [ElementInfo(key: 'button', type: 'Button')];
    native = FakeNativeBackend();
    manager = SessionManager(
      () => flutter,
      coreCommands(),
      native: NativeService(backends: {'android': native}),
    );
    expect(
      (await call('session', {
        'action': 'bind',
        'platform': 'android',
        'device': 'emulator-5554',
      })).error,
      isNull,
    );
    expect(
      (await call('connect', {'uri': 'http://localhost:1234'})).error,
      isNull,
    );
  });
  tearDown(() => manager.dispose());
  test(
    'one snapshot publishes both refs and tap routes to each source',
    () async {
      final result = await call('snapshot');
      final rows = result.data!['elements'] as List;
      final e = rows.firstWhere((r) => r['source'] == 'flutter')['ref'];
      expect((await call('tap', {'ref': e})).error, isNull);
      expect(flutter.calls.where((c) => c == 'tap'), hasLength(1));
      expect(native.taps, isEmpty);
      final n = await ref('native');
      expect((await call('tap', {'ref': n})).error, isNull);
      expect(native.taps, hasLength(1));
      expect((await call('tap', {'ref': e})).error!.code, 'STALE_REF');
    },
  );
  test(
    'swipe routes both refs and native coordinates without an inspect',
    () async {
      final e = await ref('flutter');
      expect(
        (await call('swipe', {
          'ref': e,
          'direction': 'right',
          'distance': 20,
        })).error,
        isNull,
      );
      expect(flutter.calls, contains('swipe'));
      final n = await ref('native');
      expect(
        (await call('swipe', {
          'ref': n,
          'direction': 'down',
          'distance': 20,
        })).error,
        isNull,
      );
      expect(native.calls, contains('swipe:emulator-5554'));
      expect(native.swipes, [(60.0, 40.0, 60.0, 60.0)]);
      native.calls.clear();
      expect(
        (await call('swipe', {
          'source': 'native',
          'start-x': 10,
          'start-y': 20,
          'end-x': 10,
          'end-y': 80,
        })).error,
        isNull,
      );
      expect(native.calls, ['swipe:emulator-5554']);
    },
  );
  test('native policy cannot be bypassed by unified tap or swipe', () async {
    for (final command in ['tap', 'swipe']) {
      final n = await ref('native');
      native.calls.clear();
      final result = await manager.handle(
        Request(
          requestId: 'deny',
          session: 'a',
          command: command,
          params: {'ref': n, if (command == 'swipe') 'direction': 'down'},
          policy: {
            'deny': ['native'],
          },
          deadline: DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      expect(result.error!.code, 'ACTION_DENIED');
      expect(native.calls, isEmpty);
    }
  });
  test(
    'batch shares source routing and enforces native policy before input',
    () async {
      final steps = [
        {
          'command': 'tap',
          'params': {'key': 'button'},
        },
        {
          'command': 'tap',
          'params': {'source': 'native', 'text': 'Allow'},
        },
        {
          'command': 'swipe',
          'params': {
            'source': 'native',
            'text': 'Allow',
            'direction': 'down',
            'distance': 20,
          },
        },
        {'command': 'snapshot', 'params': <String, Object?>{}},
      ];
      final denied = await manager.handle(
        Request(
          requestId: 'batch-denied',
          session: 'a',
          command: 'batch',
          params: {'steps': steps},
          policy: {
            'deny': ['native'],
          },
          deadline: DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      expect(denied.error!.code, 'ACTION_DENIED');
      expect(flutter.calls, isNot(contains('tap')));
      expect(native.taps, isEmpty);
      final allowed = await manager.handle(
        Request(
          requestId: 'batch-allowed',
          session: 'a',
          command: 'batch',
          params: {'steps': steps},
          policy: {'default': 'allow'},
          deadline: DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      expect(allowed.error, isNull);
      expect(flutter.calls.where((call) => call == 'tap'), hasLength(1));
      expect(native.taps, hasLength(1));
      expect(native.swipes, hasLength(1));
      final rows =
          ((allowed.data!['results'] as List).last['data']['elements'] as List);
      final n = rows.firstWhere((row) => row['source'] == 'native')['ref'];
      expect((await call('tap', {'ref': n})).error, isNull);
    },
  );
  test(
    'workflow final snapshot publishes usable refs for both sources',
    () async {
      final result = await call('workflow', {
        'workflow': {
          'schemaVersion': 1,
          'name': 'mixed',
          'steps': [
            {
              'id': 'tap',
              'action': 'tap',
              'target': {'key': 'button'},
            },
            {'id': 'snapshot', 'action': 'snapshot'},
          ],
        },
        'inputs': <String, Object?>{},
      });
      expect(result.error, isNull);
      final rows = asJson(result.data!['finalSnapshot'])['elements'] as List;
      expect(rows.map((row) => row['source']).toSet(), {'native', 'flutter'});
      final n = rows.firstWhere((row) => row['source'] == 'native')['ref'];
      expect((await call('tap', {'ref': n})).error, isNull);
    },
  );
  test(
    'rebind retires both refs, including a pending native approval',
    () async {
      final n = await ref('native');
      final pending = await manager.handle(
        Request(
          requestId: 'pending',
          session: 'a',
          command: 'tap',
          params: {'ref': n},
          policy: {
            'confirm': ['native'],
          },
          deadline: DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      await call('session', {
        'action': 'bind',
        'platform': 'android',
        'device': 'emulator-5556',
      });
      expect(
        (await call('confirm', {
          'id': pending.error!.details!['confirmationId'],
        })).error!.code,
        'INVALID_ARGUMENT',
      );
      expect(native.taps, isEmpty);
    },
  );
  test('failed mixed observation never retains either source', () async {
    await ref('native');
    flutter.hooks['inspect'] = () async =>
        throw const AgentError('BACKEND_ERROR', 'unavailable');
    expect((await call('snapshot')).error!.code, 'BACKEND_ERROR');
    expect(manager.sessions['a']!.observation, isNull);
    expect(manager.sessions['a']!.nativeObservation, isNull);
  });
  test('late native read cannot erase refs published after timeout', () async {
    final release = Completer<void>();
    native.inspecting = release;
    final timedOut = await manager.handle(
      Request(
        requestId: 'late-native',
        session: 'a',
        command: 'snapshot',
        params: {'source': 'native'},
        deadline: DateTime.now().add(const Duration(milliseconds: 30)),
      ),
    );
    expect(timedOut.error!.code, 'TIMEOUT');
    native.inspecting = null;
    final fresh = await call('snapshot', {'source': 'native'});
    final n = (fresh.data!['elements'] as List).first['ref'];
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((await call('tap', {'ref': n})).error, isNull);
    expect(native.taps, hasLength(1));
  });
  test(
    'known native modal suppresses Flutter refs and blocks selector input',
    () async {
      native.elements = [
        const NativeElement(
          type: 'Alert',
          bounds: NativeBounds(10, 10, 200, 200),
          enabled: true,
        ),
        nativeButton(),
      ];
      final result = await call('snapshot');
      final row = (result.data!['elements'] as List).firstWhere(
        (r) => r['source'] == 'flutter',
      );
      expect(row['ref'], isNull);
      expect(row['reason'], 'blocked_by_native_modal');
      expect(
        (await call('tap', {'key': 'button'})).error!.code,
        'UNRESOLVABLE_TARGET',
      );
      expect(flutter.calls, isNot(contains('tap')));
    },
  );
  test('source conflict and unsupported operation never send', () async {
    final n = await ref('native');
    expect(
      (await call('tap', {'ref': n, 'source': 'flutter'})).error!.code,
      'INVALID_ARGUMENT',
    );
    expect(
      (await call('fill', {'ref': n, 'input': 'text'})).error!.code,
      'UNSUPPORTED_CAPABILITY',
    );
    expect(native.taps, isEmpty);
  });
  test('max output drops both sources refs', () async {
    final result = await manager.handle(
      Request(
        requestId: 'short',
        session: 'a',
        command: 'snapshot',
        params: {},
        maxOutput: 1,
        deadline: DateTime.now().add(const Duration(seconds: 2)),
      ),
    );
    expect(result.data!['elements'], isEmpty);
    expect((await call('tap', {'ref': '@n1'})).error!.code, 'STALE_REF');
    expect((await call('tap', {'ref': '@e1'})).error!.code, 'STALE_REF');
  });
  test(
    'device queue prevents native observation overlapping Flutter input',
    () async {
      final e = await ref('flutter');
      await manager.handle(
        request(
          'session',
          session: 'b',
          params: {
            'action': 'bind',
            'platform': 'android',
            'device': 'emulator-5554',
          },
        ),
      );
      native.inspecting = Completer<void>();
      native.calls.clear();
      final observing = manager.handle(request('snapshot', session: 'b'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final tapping = call('tap', {'ref': e});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(native.calls, hasLength(1));
      expect(flutter.calls, isNot(contains('tap')));
      native.inspecting!.complete();
      expect((await observing).error, isNull);
      expect((await tapping).error, isNull);
    },
  );
}
