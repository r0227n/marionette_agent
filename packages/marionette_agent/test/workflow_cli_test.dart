import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/workflow_loader.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

import 'workflow_model_test.dart' show doc, invalidArg;
import 'session_test.dart' show request;

void main() {
  late Directory directory;
  late String runtimePath;
  late File file;
  final cliPath = File('test/support/workflow_cli.dart').absolute.path;
  Future<ProcessResult> cli(List<String> args, {String? input}) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [cliPath, '--json', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtimePath},
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    if (input != null) process.stdin.write(input);
    await process.stdin.close();
    return ProcessResult(
      process.pid,
      await process.exitCode,
      await output,
      await errors,
    );
  }

  Json body(ProcessResult r) {
    expect(r.stderr, '');
    return asJson(jsonDecode(r.stdout as String));
  }

  setUp(() async {
    directory = await Directory('/tmp').createTemp('mra-flow-');
    runtimePath = '${directory.path}/runtime';
    file = File('${directory.path}/flow.json')
      ..writeAsStringSync(jsonEncode(doc()));
  });
  tearDown(() async {
    if (Directory(runtimePath).existsSync()) {
      await cli(['close']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await directory.delete(recursive: true);
  });
  test(
    'response size failure preserves session and reports unknown progress',
    () async {
      final runtime = await RuntimeDirectory.prepare(directory: runtimePath);
      final backend = FakeBackend()
        ..elements = [ElementInfo(key: 'button', text: 'x' * maxFrameBytes)];
      final server = DaemonServer(
        runtime,
        SessionManager(() => backend, coreCommands()),
      );
      final serving = server.run();
      try {
        while (!File(runtime.metadata).existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final client = DaemonClient(runtime);
        await client.send(
          request('connect', params: {'uri': 'http://localhost:1/'}),
        );
        final result = await client.send(
          request(
            'workflow',
            ms: 10000,
            params: {
              'workflow': doc([
                {
                  'id': 'tap',
                  'action': 'tap',
                  'target': {'key': 'button'},
                },
                {'id': 'end', 'action': 'snapshot'},
              ]),
              'inputs': <String, Object?>{},
            },
          ),
        );
        expect(backend.calls.where((c) => c == 'tap').length, 1);
        expect(result.session, 'a');
        expect(result.error!.code, 'IO_ERROR');
        expect(result.error!.outcome, Outcome.unknown);
        expect(result.error!.details!['progressKnown'], false);
        expect(result.error!.details!['completedSteps'], isNull);
      } finally {
        await server.close();
        await serving;
      }
    },
  );
  test('large YAML parsing and local validation respect the absolute deadline', () async {
    final large = File('${directory.path}/large.yaml')
      ..writeAsStringSync(
        'schemaVersion: 1\nname: example\nsteps:\n${List.generate(100, (i) => '  - id: step$i\n    action: fill\n    target: {key: field}\n    text: {literal: "${'a' * 9000}"}\n').join()}',
      );
    final deadline = DateTime.now().add(const Duration(milliseconds: 30));
    try {
      await loadWorkflowFile(large.path, 'yaml', deadline);
      expect(
        DateTime.now().isAfter(deadline),
        false,
        reason: 'Successful parse must not exceed its deadline',
      );
    } on AgentError catch (error) {
      expect(error.code, 'TIMEOUT');
    }
    final result = await cli([
      '--timeout',
      '30',
      'workflow',
      'validate',
      large.path,
    ]);
    expect(result.exitCode, 5);
    expect((body(result)['error'] as Map)['code'], 'TIMEOUT');
    expect(Directory(runtimePath).existsSync(), false);
  });
  test('parser placement and rejects irrelevant/duplicate options', () {
    final parser = CliParser();
    expect(
      parser.parse(['workflow', 'schema', 'tap', '--json']).resultSession,
      isNull,
    );
    expect(
      parser.parse([
        'workflow',
        'run',
        'flow.json',
        '--session',
        'demo',
        '--timeout',
        '123',
      ]).session,
      'demo',
    );
    for (final args in [
      ['workflow', 'schema', 'tap', '--format', 'json'],
      ['workflow', 'run', 'flow.json', '--check-inputs'],
      [
        'workflow',
        'validate',
        '-',
        '--format',
        'json',
        '--inputs',
        '-',
        '--inputs-format',
        'yaml',
      ],
      ['workflow', 'validate', 'flow.json', '--inputs-format', 'json'],
      [
        'workflow',
        'validate',
        'flow.json',
        '--format',
        'json',
        '--format',
        'yaml',
      ],
      ['workflow', 'validate', 'flow.json', '--json', '--json'],
      ['workflow', 'run', 'flow.json', 'extra'],
    ]) {
      expect(() => parser.parse(args), invalidArg);
    }
  });
  test('standalone wait crosses IPC and uses the common deadline', () async {
    expect(body(await cli(['connect', 'http://localhost:1/']))['ok'], true);
    final found = body(await cli(['wait', '--key', 'button']));
    expect(found['data'], {'state': 'exists', 'requiresSnapshot': true});

    final missing = body(
      await cli([
        'wait',
        '--key',
        'absent',
        '--poll-interval',
        '50',
        '--timeout',
        '80',
      ]),
    );
    expect((missing['error'] as Map)['code'], 'TIMEOUT');
    expect((missing['error'] as Map)['outcome'], 'not_sent');
  });
  test('schema and template/bound validation never prepare runtime, stdin and errors are private', () async {
    final schema = body(await cli(['workflow', 'schema', 'tap']));
    expect(schema['session'], isNull);
    expect((schema['data'] as Map)['action'], 'tap');
    final template = {
      ...doc([
        {
          'id': 'fill',
          'action': 'fill',
          'target': {'key': 'field'},
          'text': {'input': 'value'},
        },
      ]),
      'inputs': {
        'value': {'type': 'string', 'required': true, 'sensitive': true},
      },
    };
    file.writeAsStringSync(jsonEncode(template));
    final validated = body(await cli(['workflow', 'validate', file.path]));
    expect((validated['data'] as Map)['mode'], 'template');
    final missing = await cli([
      'workflow',
      'validate',
      file.path,
      '--check-inputs',
    ]);
    expect(missing.exitCode, 2);
    expect(body(missing)['session'], isNull);
    final bound = body(
      await cli([
        'workflow',
        'validate',
        file.path,
        '--inputs',
        '-',
        '--inputs-format',
        'json',
      ], input: '{"value":"secret-value"}'),
    );
    expect((bound['data'] as Map)['inputsValidated'], true);
    expect(jsonEncode(bound), isNot(contains('secret-value')));
    expect(
      body(
        await cli([
          'workflow',
          'validate',
          '-',
          '--format',
          'json',
        ], input: jsonEncode(doc())),
      )['ok'],
      true,
    );
    final malformed = await cli([
      'workflow',
      'validate',
      '-',
      '--format',
      'yaml',
    ], input: 'value: &secret private');
    expect(malformed.exitCode, 2);
    expect(malformed.stdout, isNot(contains('private')));
    expect(malformed.stderr, '');
    expect(
      (await cli(['workflow', 'validate', '${directory.path}/missing.json']))
          .exitCode,
      1,
    );
    expect(
      (await cli([
        'workflow',
        'validate',
        '-',
        '--format',
        'json',
      ], input: 'x' * (1024 * 1024 + 1))).exitCode,
      2,
    );
    expect(Directory(runtimePath).existsSync(), false);
  }, timeout: const Timeout(Duration(seconds: 30)));
  test(
    'separate CLI requests retain workflow ref and IPC error details',
    () async {
      expect(body(await cli(['connect', 'http://localhost:1/']))['ok'], true);
      final r = body(await cli(['workflow', 'run', file.path]));
      final snapshot = (r['data'] as Map)['finalSnapshot'] as Map;
      final ref = (snapshot['elements'] as List).first['ref'] as String;
      expect(body(await cli(['tap', ref]))['ok'], true);
      file.writeAsStringSync(
        jsonEncode(
          doc([
            {
              'id': 'first',
              'action': 'tap',
              'target': {'key': 'button'},
            },
            {
              'id': 'stop',
              'action': 'tap',
              'target': {'key': 'absent'},
            },
            {'id': 'never', 'action': 'snapshot'},
          ]),
        ),
      );
      final failure = body(await cli(['workflow', 'run', file.path]));
      expect((failure['error'] as Map)['outcome'], 'not_sent');
      expect(
        ((failure['error'] as Map)['details'] as Map)['completedSteps'],
        1,
      );
      final error = AgentError.fromJson(asJson(failure['error']));
      expect(error.withOutcome(Outcome.unknown).details, error.details);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test('stdin uses one absolute deadline even after a late chunk', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        cliPath,
        '--json',
        '--timeout',
        '150',
        'workflow',
        'validate',
        '-',
        '--format',
        'json',
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtimePath},
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    // Leave EOF pending. Allow cold Dart compilation on a loaded CI host;
    // the CLI's own 150ms absolute request deadline is unchanged.
    final code = await process.exitCode.timeout(const Duration(seconds: 15));
    expect(code, 5);
    expect((jsonDecode(await stdout) as Map)['error']['code'], 'TIMEOUT');
    expect(await stderr, '');
    await process.stdin.close();
    expect(Directory(runtimePath).existsSync(), false);
  });
  for (final mismatch in [false, true]) {
    test(
      'workflow delivery ${mismatch ? 'version mismatch is not sent' : 'loss is unknown without retry'}',
      () async {
        final runtime = await RuntimeDirectory.prepare(directory: runtimePath);
        final server = await ServerSocket.bind(
          InternetAddress(runtime.socket, type: InternetAddressType.unix),
          0,
        );
        var received = 0;
        server.listen((socket) async {
          socket.add(
            encodeFrame({
              'protocolVersion': mismatch ? 1 : protocolVersion,
              'ready': true,
            }),
          );
          await socket.flush();
          if (mismatch) {
            await socket.close();
            return;
          }
          await decodeFrames(socket).first;
          received++;
          socket.destroy();
        });
        final result = await DaemonClient(runtime).send(
          request(
            'workflow',
            params: {'workflow': doc(), 'inputs': <String, Object?>{}},
          ),
        );
        expect(result.error!.code, 'IO_ERROR');
        expect(
          result.error!.outcome,
          mismatch ? Outcome.notSent : Outcome.unknown,
        );
        expect(result.error!.details!['progressKnown'], mismatch);
        expect(result.error!.details!['completedSteps'], mismatch ? 0 : null);
        expect(received, mismatch ? 0 : 1);
        await server.close();
      },
    );
  }
}
