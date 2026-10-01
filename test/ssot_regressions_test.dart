import 'dart:async';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

void main() {
  final invalidArgument = throwsA(
    isA<AgentError>().having((error) => error.code, 'code', 'INVALID_ARGUMENT'),
  );

  test('subcommands never silently ignore parent positional arguments', () {
    final parser = CliParser(environment: {});
    for (final argv in [
      ['get', 'ignored', 'text', '--key', 'button'],
      ['is', 'ignored', 'visible', '--key', 'button'],
      ['session', 'ignored', 'list'],
    ]) {
      expect(() => parser.parse(argv), invalidArgument, reason: '$argv');
    }
    expect(parser.parse(['get', 'text', '--key', 'button']).params, {
      'action': 'text',
      'key': 'button',
    });
  });

  test('global close keeps a null session even on syntax and value errors', () {
    final parser = CliParser(environment: {});
    for (final argv in [
      ['close', '--all', '--timeout', '0'],
      ['close', '--all', '--unexpected'],
      ['close', '--all', '--all'],
    ]) {
      String? session = 'unreported';
      var json = false;
      expect(
        () => parser.parse(
          ['--json', ...argv],
          onOutput: (name, value) {
            session = name;
            json = value;
          },
        ),
        invalidArgument,
      );
      expect(session, isNull, reason: '$argv');
      expect(json, isTrue);
    }
    String? session;
    expect(
      () => parser.parse([
        'close',
        '--timeout',
        '--all',
        '--unexpected',
      ], onOutput: (name, _) => session = name),
      invalidArgument,
    );
    expect(session, 'default', reason: 'An option value is not the --all flag');
  });

  group('session execution', () {
    late FakeBackend backend;
    late SessionManager manager;
    setUp(() async {
      backend = FakeBackend()..elements = [ElementInfo(key: 'button')];
      manager = SessionManager(() => backend, coreCommands());
      expect(
        (await manager.handle(
          request('connect', params: {'uri': 'http://localhost:1/'}),
        )).error,
        isNull,
      );
      expect((await manager.handle(request('snapshot'))).error, isNull);
      backend.calls.clear();
    });
    tearDown(() => manager.dispose());

    test(
      'malformed find is rejected before policy can create a pending action',
      () async {
        for (final action in [42, 'find', 'batch', 'workflow']) {
          final result = await manager.handle(
            Request(
              requestId: 'invalid-find',
              session: 'a',
              command: 'find',
              params: {
                'by': 'key',
                'value': 'button',
                'exact': true,
                'action': action,
              },
              policy: {
                'confirm': ['tap', 'batch', 'workflow'],
              },
              deadline: DateTime.now().add(const Duration(seconds: 2)),
            ),
          );
          expect(result.error?.code, 'INVALID_ARGUMENT', reason: '$action');
          expect(result.error?.outcome, Outcome.notSent);
          expect(result.error?.details, isNull);
        }
        expect(backend.calls, isEmpty);
        expect(manager.sessions['a']!.observation, isNotNull);
      },
    );

    test(
      'all wait target forms reject explicit null options before observing',
      () async {
        for (final target in [
          {'key': 'button'},
          {'ref': '@e1'},
        ]) {
          for (final option in ['state', 'pollIntervalMs']) {
            final result = await manager.handle(
              request('wait', params: {...target, option: null}),
            );
            expect(
              result.error?.code,
              'INVALID_ARGUMENT',
              reason: '$target $option',
            );
            expect(result.error?.outcome, Outcome.notSent);
          }
        }
        expect(backend.calls, isEmpty);
        expect(manager.sessions['a']!.observation, isNotNull);
      },
    );

    test(
      'single close reports disconnect failure instead of success',
      () async {
        backend.hooks['disconnect'] = () async =>
            throw StateError('private detail');
        final result = await manager.handle(request('close'));
        expect(result.error?.code, 'BACKEND_ERROR');
        expect(result.error?.outcome, Outcome.failed);
        expect(result.toJson().toString(), isNot(contains('private detail')));
        expect(manager.sessions, isEmpty);
        expect(backend.calls, ['disconnect']);
      },
    );

    test('single close waits for disconnect only until its deadline', () async {
      final entered = Completer<void>();
      final finished = Completer<void>();
      backend.hooks['disconnect'] = () {
        entered.complete();
        return finished.future;
      };
      try {
        final closing = manager.handle(request('close', ms: 100));
        await entered.future;
        final result = await closing;
        expect(result.error?.code, 'TIMEOUT');
        expect(result.error?.outcome, Outcome.unknown);
        expect(manager.sessions, isEmpty);
        expect(backend.calls, ['disconnect']);
      } finally {
        finished.complete();
      }
    });
  });
}
