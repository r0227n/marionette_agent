import 'dart:async';

import 'package:marionette_agent/src/cli/parser.dart';
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
  late FakeNativeBackend backend;
  late SessionManager manager;
  Future<Result> call(
    String action, {
    Json params = const {},
    String session = 'a',
    String device = 'emulator-5554',
    int ms = 2000,
    int? limit,
    Json? policy,
  }) async {
    final platform = params['platform'] ?? 'android';
    final requestedDevice = params['device'] ?? device;
    if (manager.sessions[session]?.nativeTarget !=
        '$platform:$requestedDevice') {
      final bound = await manager.handle(
        request(
          'session',
          session: session,
          params: {
            'action': 'bind',
            'platform': platform,
            'device': requestedDevice,
          },
        ),
      );
      if (bound.error != null) return bound;
    }
    final clean = {...params}
      ..remove('platform')
      ..remove('device');
    final mapped = <String, dynamic>{
      for (final e in clean.entries)
        (const {
                  'startX': 'start-x',
                  'startY': 'start-y',
                  'endX': 'end-x',
                  'endY': 'end-y',
                }[e.key] ??
                e.key):
            e.value,
    };
    return manager.handle(
      Request(
        requestId: 'native',
        session: session,
        command: action,
        params: {'source': 'native', ...mapped},
        deadline: DateTime.now().add(Duration(milliseconds: ms)),
        maxOutput: limit,
        policy: policy,
      ),
    );
  }

  Future<String> snapshot({String session = 'a'}) async =>
      (((await call('snapshot', session: session)).data!['elements'] as List)
                  .first
              as Map)['ref']
          as String;
  setUp(() {
    backend = FakeNativeBackend();
    manager = SessionManager(
      FakeBackend.new,
      coreCommands(),
      native: NativeService(backends: {'android': backend}),
    );
  });
  tearDown(() async {
    await manager.handle(request('close', params: {'all': true}));
  });

  test('works without VM, reobserves before one tap and expires ref', () async {
    final ref = await snapshot();
    expect(manager.sessions['a']!.backend, isNull);
    expect((await call('tap', params: {'ref': ref})).error, isNull);
    expect(backend.calls, [
      'inspect:emulator-5554',
      'inspect:emulator-5554',
      'tap:emulator-5554',
    ]);
    expect(backend.taps, [(60.0, 40.0)]);
    expect((await call('tap', params: {'ref': ref})).error!.code, 'STALE_REF');
    expect(backend.taps, hasLength(1));
  });
  test('changed frame, device or session cannot reuse a native ref', () async {
    final ref = await snapshot();
    expect(
      (await call('tap', session: 'b', params: {'ref': ref})).error!.code,
      'STALE_REF',
    );
    expect(
      (await call(
        'tap',
        device: 'emulator-5556',
        params: {'ref': ref},
      )).error!.code,
      'STALE_REF',
    );
    backend.elements = [nativeButton(x: 11)];
    expect((await call('tap', params: {'ref': ref})).error!.code, 'STALE_REF');
    expect(backend.taps, isEmpty);
  });
  test(
    'duplicates and disabled selectors are rejected without input',
    () async {
      backend.elements = [nativeButton(), nativeButton(x: 150)];
      expect(
        (await call('tap', params: {'text': 'Allow'})).error!.code,
        'AMBIGUOUS_TARGET',
      );
      backend.elements = [nativeButton(enabled: false)];
      expect(
        (await call('tap', params: {'identifier': 'allow'})).error!.code,
        'UNRESOLVABLE_TARGET',
      );
      expect(
        (await call('tap', params: {'text': 'absent'})).error!.code,
        'TARGET_NOT_FOUND',
      );
      expect(backend.taps, isEmpty);
    },
  );
  test(
    'identical nodes never receive refs; bounds can distinguish cells',
    () async {
      backend.elements = [nativeButton(), nativeButton(), nativeButton(x: 150)];
      final rows = (await call('snapshot')).data!['elements'] as List;
      expect(rows[0]['ref'], isNull);
      expect(rows[1]['ref'], isNull);
      expect(rows[2]['ref'], startsWith('@n'));
      expect(
        (await call('tap', params: {'ref': rows[2]['ref']})).error,
        isNull,
      );
      expect(backend.taps, [(200.0, 40.0)]);
    },
  );
  test(
    'max-output removes undisclosed refs and numbering is not rewound',
    () async {
      final first = await snapshot();
      final limited = await call('snapshot', limit: 1);
      expect(limited.data!['elements'], isEmpty);
      expect(
        (await call('tap', params: {'ref': first})).error!.code,
        'STALE_REF',
      );
      expect(
        (await call('tap', params: {'ref': '@n2'})).error!.code,
        'STALE_REF',
      );
      expect(await snapshot(), '@n3');
    },
  );
  test('native action invalidates same-device refs across sessions and Flutter refs', () async {
    final a = await snapshot();
    final b = await snapshot(session: 'b');
    await manager.handle(
      request(
        'connect',
        session: 'flutter',
        params: {'uri': 'http://localhost:1234'},
      ),
    );
    await manager.handle(request('snapshot', session: 'flutter'));
    expect(manager.sessions['flutter']!.observation, isNotNull);
    expect((await call('tap', params: {'ref': a})).error, isNull);
    expect(manager.sessions['flutter']!.observation, isNull);
    expect(
      (await call('tap', session: 'b', params: {'ref': b})).error!.code,
      'STALE_REF',
    );
  });
  test('Flutter action invalidates native refs in that session', () async {
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1234'}),
    );
    final ref = await snapshot();
    await manager.handle(request('tap', params: {'x': 10, 'y': 10}));
    expect((await call('tap', params: {'ref': ref})).error!.code, 'STALE_REF');
  });
  test(
    'policy denies mutation before observation; reads remain available',
    () async {
      final denied = await call(
        'tap',
        params: {'text': 'Allow'},
        policy: {
          'deny': ['native'],
        },
      );
      expect(denied.error!.code, 'ACTION_DENIED');
      expect(backend.calls, isEmpty);
      expect((await call('snapshot')).error, isNull);
    },
  );
  test(
    'confirmation remains one-use and runs fresh target validation',
    () async {
      final pending = await call(
        'tap',
        params: {'text': 'Allow'},
        policy: {
          'confirm': ['native'],
        },
      );
      final id = pending.error!.details!['confirmationId'];
      backend.elements = [nativeButton(), nativeButton(x: 150)];
      expect(
        (await manager.handle(request('confirm', params: {'id': id})))
            .error!
            .code,
        'AMBIGUOUS_TARGET',
      );
      expect(
        (await manager.handle(request('confirm', params: {'id': id})))
            .error!
            .code,
        'INVALID_ARGUMENT',
      );
      expect(backend.taps, isEmpty);
    },
  );
  test('timeout in observation never dispatches late', () async {
    backend.inspecting = Completer<void>();
    final result = await call('tap', params: {'text': 'Allow'}, ms: 30);
    expect(result.error!.code, 'TIMEOUT');
    expect(result.error!.outcome, Outcome.notSent);
    backend.inspecting!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.taps, isEmpty);
  });
  test('post-dispatch tool failure is unknown and not retried', () async {
    backend.failure = const PlatformException('IO_ERROR', 'failed');
    final result = await call('tap', params: {'text': 'Allow'});
    expect(result.error!.outcome, Outcome.unknown);
    expect(backend.taps, hasLength(1));
  });
  test(
    'explicit coordinates work without an accessibility observation',
    () async {
      backend.inspecting = Completer<void>();
      expect((await call('tap', params: {'x': 10, 'y': 20})).error, isNull);
      expect(
        (await call(
          'swipe',
          params: {'startX': 10, 'startY': 20, 'endX': 10, 'endY': 200},
        )).error,
        isNull,
      );
      expect(backend.calls, ['tap:emulator-5554', 'swipe:emulator-5554']);
    },
  );
  test('post-dispatch timeout returns unknown and never replays', () async {
    backend.tapping = Completer<void>();
    final result = await call('tap', params: {'x': 25, 'y': 35}, ms: 30);
    expect(result.error!.outcome, Outcome.unknown);
    backend.tapping!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.taps, [(25.0, 35.0)]);
  });
  test('device queue rejects expired requests from another session', () async {
    backend.inspecting = Completer<void>();
    final first = call('snapshot');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final result = await call(
      'tap',
      session: 'b',
      params: {'text': 'Allow'},
      ms: 30,
    );
    expect(result.error!.code, 'TIMEOUT');
    backend.inspecting!.complete();
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.calls, ['inspect:emulator-5554']);
  });
  test(
    'IPC rejects unexpected fields and invalid devices before inspection',
    () async {
      for (final params in [
        {'unknown': true},
        {'platform': 'web'},
        {'device': 'booted', 'platform': 'ios'},
        {'text': 'Allow', 'x': 1, 'y': 2},
        {'x': double.infinity, 'y': 1},
        {'ref': '@e1'},
        {'text': ''},
        {'x': 1},
      ]) {
        expect(
          (await call('tap', params: params)).error!.code,
          'INVALID_ARGUMENT',
        );
      }
      expect(backend.calls, isEmpty);
    },
  );
  test('close disposes native-only sessions and old refs', () async {
    final ref = await snapshot();
    expect((await manager.handle(request('close'))).error, isNull);
    expect(manager.sessions, isEmpty);
    expect(ref, startsWith('@n'));
  });
  test('CLI validates targets, paths, duplicates and explicit device', () {
    final parser = CliParser(environment: {});
    final opts = ['--platform=android', '--device=emulator-5554'];
    expect(
      parser.parse(['tap', '--source=native', '--text=Allow']).params['text'],
      'Allow',
    );
    expect(parser.parse(['tap', '@n1']).params['ref'], '@n1');
    for (final args in [
      ['native'],
      ['native', 'screenshot', ...opts],
      ['native', 'snapshot'],
      ['native', 'snapshot', ...opts, 'unexpected'],
      ['native', 'tap', ...opts, '@e1'],
      ['native', 'tap', ...opts],
      ['native', 'tap', ...opts, '@n1', '--text=Allow'],
      ['native', 'snapshot', ...opts, '--device=other'],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });
}
