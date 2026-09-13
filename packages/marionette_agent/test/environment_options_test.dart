import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'idle_timeout_test.dart' show eventually;
import 'support/fake_backend.dart';
import 'support/requests.dart';

void main() {
  const environment = {
    'MARIONETTE_AGENT_SESSION': 'env-session',
    'MARIONETTE_AGENT_TIMEOUT_MS': '1234',
  };
  final invalidArgument = throwsA(
    isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
  );

  test(
    'unset, environment and explicit values have deterministic precedence',
    () {
      final defaults = CliParser(environment: {}).parse(['snapshot']);
      expect(defaults.session, 'default');
      expect(defaults.timeoutMs, 30000);
      final parser = CliParser(environment: environment);
      final selected = parser.parse(['snapshot']);
      expect(selected.session, 'env-session');
      expect(selected.timeoutMs, 1234);
      for (final command in [
        ['snapshot'],
        ['session', 'show'],
        ['session', 'list'],
        ['workflow', 'schema'],
        ['record', 'status'],
        ['--help'],
        ['--version'],
      ]) {
        for (final args in [
          ['--session=cli', '--timeout=2345', ...command],
          [...command, '--session', 'cli', '--timeout', '2345'],
        ]) {
          final value = parser.parse(args);
          expect(value.session, 'cli');
          expect(value.timeoutMs, 2345);
        }
      }
      expect(parser.parse(['snapshot', '--session=cli']).timeoutMs, 1234);
      expect(
        parser.parse(['snapshot', '--timeout=2345']).session,
        'env-session',
      );
      expect(parser.usage, contains('MARIONETTE_AGENT_SESSION'));
      expect(parser.usage, contains('MARIONETTE_AGENT_TIMEOUT_MS'));
    },
  );

  test(
    'validate only selected values, including empty and out-of-range values',
    () {
      for (final entry in {
        'MARIONETTE_AGENT_SESSION': ['', '../bad', '_bad', 'a b', 'a' * 65],
        'MARIONETTE_AGENT_TIMEOUT_MS': [
          '', '0', '-1', '+1', '1.5', ' 1', '1 ', '1s', 'NaN',
          '9223372036854776', // Duration overflow.
          '9223372036854775', // DateTime overflow.
          '999999999999999999999999999999',
        ],
      }.entries) {
        final option = entry.key.endsWith('SESSION') ? 'session' : 'timeout';
        final valid = option == 'session' ? 'cli' : '5000';
        for (final value in entry.value) {
          final parser = CliParser(
            environment: {...environment, entry.key: value},
          );
          expect(
            () => parser.parse(['snapshot']),
            invalidArgument,
            reason: value,
          );
          expect(
            parser.parse(['snapshot', '--$option=$valid']).command,
            'snapshot',
          );
          expect(
            () =>
                CliParser(environment: environment)
                    .parse(['snapshot', '--$option=$value']),
            invalidArgument,
          );
        }
      }
      final valid = CliParser(
        environment: {
          'MARIONETTE_AGENT_SESSION': 'a' * 64,
          'MARIONETTE_AGENT_TIMEOUT_MS': '0001',
        },
      ).parse(['snapshot']);
      expect(valid.session.length, 64);
      expect(valid.timeoutMs, 1);
    },
  );

  test(
    'duplicates and missing explicit values do not fall back to environment',
    () {
      for (final args in [
        ['--session=a', 'snapshot', '--session=b'],
        ['--timeout=12', 'snapshot', '--timeout=13'],
        ['snapshot', '--session'],
        ['snapshot', '--timeout'],
      ]) {
        expect(
          () => CliParser(environment: environment).parse(args),
          invalidArgument,
        );
      }
    },
  );

  test(
    'syntax recovery uses selected session and respects values and terminator',
    () {
      for (final sample in <(List<String>, String?, bool)>[
        (['--json', 'snapshot', '--bad'], 'env-session', true),
        (['snapshot', '--session=cli', '--json', '--bad'], 'cli', true),
        (['snapshot', '--session=../bad', '--json', '--bad'], null, true),
        (['snapshot', '--json', '--session'], null, true),
        (
          ['fill', '@e1', '--key', '--session=literal', '--bad'],
          'env-session',
          false,
        ),
        (['fill', '@e1', '--timeout', '--json', '--bad'], 'env-session', false),
        (
          ['--bad', 'fill', '@e1', '--', '--session=literal', '--json'],
          'env-session',
          false,
        ),
        (['session', 'list', '--json', '--bad'], null, true),
        (['workflow', 'schema', '--json', '--bad'], null, true),
        (['--help', '--json', '--bad'], null, true),
      ]) {
        String? session;
        var json = false;
        expect(
          () => CliParser(environment: environment).parse(
            sample.$1,
            onOutput: (s, j) {
              session = s;
              json = j;
            },
          ),
          invalidArgument,
        );
        expect(session, sample.$2, reason: '${sample.$1}');
        expect(json, sample.$3, reason: '${sample.$1}');
      }
      final literal = CliParser(environment: environment)
          .parse(['fill', '@e1', '--', '--session=literal']);
      expect(literal.session, 'env-session');
      expect(literal.params['input'], '--session=literal');
      for (final bad in ['', '../bad']) {
        String? session = 'unexpected';
        expect(
          () => CliParser(environment: {'MARIONETTE_AGENT_SESSION': bad}).parse(
            ['snapshot', '--json', '--bad'],
            onOutput: (s, _) => session = s,
          ),
          invalidArgument,
        );
        expect(session, isNull);
      }
    },
  );

  group('isolated product CLI processes', () {
    late Directory directory;
    late RuntimeDirectory runtime;
    late FakeBackend backend;
    late SessionManager manager;
    late DaemonServer server;
    late Future<void> running;
    final script = File('bin/marionette_agent.dart').absolute.path;
    Future<ProcessResult> cli(
      List<String> args, {
      Map<String, String> env = environment,
    }) => Process.run(
      Platform.resolvedExecutable,
      [script, ...args],
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH']!,
        'HOME': Platform.environment['HOME']!,
        'MARIONETTE_AGENT_RUNTIME_DIR': directory.path,
        ...env,
      },
    );
    Json body(ProcessResult result, int code) {
      expect(
        result.exitCode,
        code,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(result.stderr, isEmpty);
      return asJson(jsonDecode(result.stdout as String));
    }

    setUp(() async {
      directory = await Directory('/tmp').createTemp('mra-env-');
      await Process.run('chmod', ['700', directory.path]);
      runtime = await RuntimeDirectory.prepare(directory: directory.path);
      backend = FakeBackend()
        ..elements = [ElementInfo(key: 'button', type: 'Button')];
      manager = SessionManager(() => backend, coreCommands());
      server = DaemonServer(runtime, manager, idleTimeoutMs: 0);
      running = server.run();
      await eventually(() => File(runtime.metadata).existsSync());
    });
    tearDown(() async {
      await server.close();
      await running;
      await directory.delete(recursive: true);
    });

    test('environment session persists across processes, explicit session stays separate', () async {
      expect(
        body(
          await cli(['connect', 'http://localhost:1/', '--json']),
          0,
        )['session'],
        'env-session',
      );
      final snapshot = body(await cli(['snapshot', '--json']), 0);
      expect(snapshot['session'], 'env-session');
      expect(asJson(snapshot['data'])['elements'], isNotEmpty);
      final text = await cli(['snapshot']);
      expect(text.exitCode, 0);
      expect(text.stdout, contains('button'));
      expect(
        body(
          await cli(['snapshot', '--session=other', '--json']),
          3,
        )['session'],
        'other',
      );
      final explicit = body(
        await cli(
          [
            '--session=env-session',
            '--timeout=30000',
            'session',
            'show',
            '--json',
          ],
          env: {
            'MARIONETTE_AGENT_SESSION': '',
            'MARIONETTE_AGENT_TIMEOUT_MS': 'invalid',
          },
        ),
        0,
      );
      expect(explicit['session'], 'env-session');
      expect(body(await cli(['close', '--json']), 0)['session'], 'env-session');
    });

    test(
      'selected invalid environment returns text/JSON errors before dispatch',
      () async {
        for (final sample in <(Map<String, String>, String?)>[
          ({'MARIONETTE_AGENT_SESSION': ''}, null),
          ({'MARIONETTE_AGENT_SESSION': '../bad'}, null),
          ({...environment, 'MARIONETTE_AGENT_TIMEOUT_MS': ''}, 'env-session'),
          (
            {...environment, 'MARIONETTE_AGENT_TIMEOUT_MS': '9223372036854775'},
            'env-session',
          ),
        ]) {
          final value = body(
            await cli(['snapshot', '--json'], env: sample.$1),
            2,
          );
          expect(value['session'], sample.$2);
          expect(asJson(value['error'])['code'], 'INVALID_ARGUMENT');
          expect(asJson(value['error'])['outcome'], 'not_sent');
        }
        final text = await cli(
          ['snapshot'],
          env: {...environment, 'MARIONETTE_AGENT_TIMEOUT_MS': '0'},
        );
        expect(text.exitCode, 2);
        expect(text.stdout, contains('INVALID_ARGUMENT'));
        expect(text.stdout, contains('Outcome: not_sent'));
        final syntax = body(await cli(['snapshot', '--bad', '--json']), 2);
        expect(syntax['session'], 'env-session');
        final defaults = body(await cli(['snapshot', '--json'], env: {}), 3);
        expect(defaults['session'], 'default');
        expect(backend.calls, isEmpty);
      },
    );

    test(
      'environment deadline expires while queued without sending the operation',
      () async {
        body(await cli(['connect', 'http://localhost:1/', '--json']), 0);
        final entered = Completer<void>();
        final release = Completer<void>();
        backend.hooks['inspect'] = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        final blocking = manager.handle(
          request('snapshot', session: 'env-session'),
        );
        await entered.future;
        try {
          final queued = body(
            await cli(
              ['tap', '--key=button', '--json'],
              env: {...environment, 'MARIONETTE_AGENT_TIMEOUT_MS': '200'},
            ),
            5,
          );
          expect(queued['session'], 'env-session');
          expect(asJson(queued['error'])['code'], 'TIMEOUT');
          expect(asJson(queued['error'])['outcome'], 'not_sent');
          expect(manager.sessions['env-session']!.pending, 2);
          expect(backend.calls.where((v) => v == 'inspect'), hasLength(1));
          expect(backend.calls, isNot(contains('tap')));
        } finally {
          release.complete();
          expect((await blocking).exitCode, 0);
        }
        body(await cli(['snapshot', '--json']), 0);
        expect(backend.calls, isNot(contains('tap')));
      },
    );
  });
}
