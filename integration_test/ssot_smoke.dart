import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Caller owns a fresh example app/Simulator and a private output directory.
Future<void> main() async {
  final env = Platform.environment;
  final root = Directory(env['MARIONETTE_TEST_PRIVATE']!).absolute;
  final uri = File(env['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final runtime = p.join(root.path, 'runtime');
  final evidence = Directory(p.join(root.path, 'evidence'));
  final cliPath = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin',
    'marionette_agent.dart',
  );
  final records = <Map<String, Object?>>[];
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<Map<String, dynamic>> cli(
    List<String> args, {
    int expected = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        cliPath,
        '--json',
        if (!args.contains('--timeout')) ...['--timeout', '30000'],
        ...args,
      ],
      environment: {
        'MARIONETTE_AGENT_RUNTIME_DIR': runtime,
        'MARIONETTE_AGENT_SESSION': 'ssot-review',
      },
    );
    final out = result.stdout as String;
    final err = result.stderr as String;
    records.add({
      'args': [for (final arg in args) arg == uri ? '<VM_URI>' : arg],
      'exitCode': result.exitCode,
      'stdout': out.replaceAll(uri, '<VM_URI>'),
      'stderr': err.replaceAll(uri, '<VM_URI>'),
    });
    check(!out.contains(uri) && !err.contains(uri), 'URI must stay private');
    check(
      result.exitCode == expected,
      '${args.first}: expected exit $expected, got ${result.exitCode}',
    );
    return jsonDecode(out) as Map<String, dynamic>;
  }

  Future<void> count(int value) async {
    final result = await cli(['get', 'text', '--key', 'tap_result']);
    check(result['data']['text'] == 'Tap count: $value', 'Unexpected UI count');
  }

  Future<void> confirm(List<String> args) async {
    final pending = await cli(args, expected: 1);
    check(
      pending['error']['code'] == 'CONFIRMATION_REQUIRED',
      'Expected approval',
    );
    final id = pending['error']['details']['confirmationId'] as String;
    await cli(['confirm', id]);
    final reused = await cli(['confirm', id], expected: 2);
    check(reused['error']['code'] == 'INVALID_ARGUMENT', 'Approval was reused');
  }

  var connected = false;
  var passed = false;
  try {
    for (final args in [
      ['close', '--all', '--timeout', '0'],
      ['close', '--all', '--unexpected'],
    ]) {
      final result = await cli(args, expected: 2);
      check(result['session'] == null, 'Global error must have null session');
      check(!Directory(runtime).existsSync(), 'Syntax error created runtime');
    }
    await cli(['connect', uri]);
    connected = true;
    await count(0);
    final snapshot = await cli(['snapshot']);
    final ref =
        (snapshot['data']['elements'] as List).cast<Map>().singleWhere(
              (row) => row['key'] == 'tap_button',
            )['ref']
            as String;
    await cli(['wait', ref, '--poll-interval', '50']);
    await cli(['wait', '--key', 'tap_button', '--poll-interval', '1000']);
    await cli(['wait', '0']);
    await cli(['wait', ref, '--poll-interval', '49'], expected: 2);
    await cli(['wait', ref, '--poll-interval', '1001'], expected: 2);
    await cli(['get', 'text', ref]);
    await cli(['screenshot', p.join(evidence.path, 'before-confirm.png')]);
    await confirm([
      '--confirm-actions',
      'tap',
      'find',
      'key',
      'tap_button',
      'tap',
    ]);
    await count(1);
    final batchFile = File(p.join(root.path, 'batch.json'));
    await batchFile.writeAsString(
      jsonEncode([
        ['find', 'key', 'tap_button', 'click'],
        ['wait', '0'],
        ['get', 'text', '--key', 'tap_result'],
      ]),
    );
    await confirm(['batch', batchFile.path]);
    await count(2);
    final workflow = File(p.join(root.path, 'workflow.json'));
    await workflow.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'name': 'ssot-review',
        'steps': [
          {
            'id': 'tap',
            'action': 'tap',
            'target': {'key': 'tap_button'},
          },
          {
            'id': 'wait',
            'action': 'wait',
            'target': {'key': 'tap_button'},
            'state': 'exists',
            'pollIntervalMs': 50,
          },
          {'id': 'observe', 'action': 'snapshot'},
        ],
      }),
    );
    await confirm(['workflow', 'run', workflow.path]);
    await count(3);
    final deniedPolicy = File(p.join(root.path, 'deny.json'));
    await deniedPolicy.writeAsString(
      jsonEncode({
        'deny': ['tap'],
      }),
    );
    final denied = await cli([
      '--action-policy',
      deniedPolicy.path,
      'find',
      'key',
      'tap_button',
      'click',
    ], expected: 1);
    check(
      denied['error']['code'] == 'ACTION_DENIED',
      'Alias must share policy',
    );
    await count(3);
    await cli(['screenshot', p.join(evidence.path, 'after-operations.png')]);
    await cli(['close']);
    connected = false;
    final absent = await cli(['session', 'list']);
    check(
      (absent['data']['sessions'] as List).isEmpty,
      'Session remained after close',
    );
    await cli(['connect', uri]);
    connected = true;
    await count(3);
    final closed = await cli(['close', '--all']);
    connected = false;
    check(closed['session'] == null, 'Global close must have null session');
    check(
      closed['data']['sessions'].length == 1,
      'Expected one closed session',
    );
    passed = true;
  } finally {
    if (connected) await cli(['close']);
    await File(p.join(evidence.path, 'results.json')).writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'passed': passed, 'calls': records}),
    );
  }
  stdout.writeln(
    'PASS: ${records.length} CLI calls; evidence: ${evidence.path}',
  );
}
