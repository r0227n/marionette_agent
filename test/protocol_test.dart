import 'package:args/args.dart';

import 'dart:convert';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('debug IPC policy is opt-in and strictly typed', () {
    final request = Request(
      requestId: 'test-1',
      session: 'demo',
      command: 'snapshot',
      params: {},
      deadline: DateTime.now(),
      debug: true,
    );
    expect(Request.fromJson(request.toJson()).debug, isTrue);
    final legacy = request.toJson()..remove('debug');
    expect(Request.fromJson(legacy).debug, isFalse);
    expect(
      () => Request.fromJson({...legacy, 'debug': 'true'}),
      throwsA(isA<AgentError>()),
    );
  });

  test('debug recovery respects literals and rejects duplicate flags', () {
    for (final pair in <(List<String>, bool)>[
      (['--debug', 'snapshot', '--unknown'], true),
      (['snapshot', '--timeout', 'bad', '--debug'], true),
      (['fill', '--text', '--debug', '--unknown'], false),
      (['snapshot', '--', '--debug'], false),
    ]) {
      var debug = false;
      expect(
        () => CliParser().parse(pair.$1, onDebug: (value) => debug = value),
        throwsA(isA<AgentError>()),
      );
      expect(debug, pair.$2);
    }
    expect(
      () => CliParser().parse(['--debug', 'snapshot', '--debug']),
      throwsA(isA<AgentError>()),
    );
  });
  test('common options anywhere, literal values and registry', () {
    final parser = CliParser(
      commands: {
        'custom': CliCommand(
          ArgParser(),
          (args) => {'value': args.rest.single},
        ),
      },
    );
    final value = parser.parse([
      '--session',
      'demo',
      'custom',
      '--json',
      '--',
      '--secret',
    ]);
    expect(value.params, {'value': '--secret'});
    expect(value.session, 'demo');
    expect(value.json, isTrue);
    expect(
      parser.parse(['connect', 'http://localhost/', '--timeout=123']).timeoutMs,
      123,
    );
    expect(parser.parse(['session', 'list']).resultSession, isNull);
  });
  test('invalid common options and argument counts', () {
    for (final args in [
      <String>[],
      ['snapshot', '--session', '../x'],
      ['--timeout=0', 'snapshot'],
      ['--json', 'snapshot', '--json'],
      ['connect'],
      ['close', 'x'],
      ['snapshot', '--wat'],
      ['--session=a', 'snapshot', '--session=b'],
      ['--json=false'],
      ['--timeout=NaN'],
    ]) {
      expect(
        () => CliParser().parse(args),
        throwsA(isA<AgentError>().having((e) => e.exitCode, 'exit', 2)),
      );
    }
  });
  test('all exit classes and round trip envelopes', () {
    for (final pair in {
      'INVALID_ARGUMENT': 2,
      'NOT_CONNECTED': 3,
      'STALE_REF': 4,
      'TIMEOUT': 5,
      'UNSUPPORTED_CAPABILITY': 6,
      'BACKEND_ERROR': 1,
    }.entries) {
      final result = Result.failure(
        'demo',
        AgentError(pair.key, 'Safe message', outcome: Outcome.unknown),
      );
      final round = Result.fromJson(
        asJson(jsonDecode(render(result, json: true))),
      );
      expect(round.exitCode, pair.value);
      expect(round.error!.outcome, Outcome.unknown);
      expect(round.data, isNull);
    }
    expect(
      Result.fromJson(Result.success(null, {'version': version}).toJson())
          .exitCode,
      0,
    );
  });
  test(
    'framing handles fragmented and multiple responses, rejects truncation',
    () async {
      final bytes = encodeFrame({'value': 'Japanese'});
      expect(
        await decodeFrames(
          Stream.fromIterable([bytes.sublist(0, 3), bytes.sublist(3), bytes]),
        ).toList(),
        [
          {'value': 'Japanese'},
          {'value': 'Japanese'},
        ],
      );
      await expectLater(
        decodeFrames(Stream.value([123])).toList(),
        throwsA(isA<AgentError>()),
      );
      expect(
        () => Request.fromJson({'protocolVersion': 0}),
        throwsA(isA<AgentError>()),
      );
    },
  );
}
