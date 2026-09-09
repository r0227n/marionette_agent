import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Smoke test for independent CLI processes against a running example app instance.
/// Read the VM URI from a file and do not print it to arguments, logs, or evidence.
Future<void> main() async {
  final uriFile = Platform.environment['MARIONETTE_TEST_VM_URI_FILE'];
  if (uriFile == null) throw StateError('Set MARIONETTE_TEST_VM_URI_FILE');
  final uri = (await File(uriFile).readAsString()).trim();
  final runtime = await Directory('/tmp').createTemp('mra-smoke-');
  await Process.run('chmod', ['700', runtime.path]);
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final production = p.join(root, 'bin', 'marionette_agent.dart');
  final probe = p.join(root, 'integration_test', 'support', 'probe_cli.dart');
  final evidence = <Map<String, Object?>>[];
  Future<Map<String, dynamic>> cli(
    List<String> args, {
    bool testCommand = false,
    int expected = 0,
    String session = 'sim',
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        testCommand ? probe : production,
        '--json',
        '--session',
        session,
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final diagnostics = (result.stderr as String)
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
    if (result.exitCode != expected) {
      throw StateError(
        'CLI failed (exit ${result.exitCode}, expected $expected)',
      );
    }
    if (diagnostics.any((line) => line.contains(uri))) {
      throw StateError('CLI diagnostics exposed the VM Service URI');
    }
    if (args.first == 'connect' &&
        expected == 0 &&
        !diagnostics.any(
          (line) => line.contains('Connecting to VM service at <redacted-uri>'),
        )) {
      throw StateError('CLI did not emit the redacted connection diagnostic');
    }
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    evidence.add({
      'session': session,
      'command': args.first == 'connect' ? 'connect <VM_URI>' : args.join(' '),
      'exitCode': result.exitCode,
      'diagnostics': diagnostics,
      'result': json,
    });
    return json;
  }

  int tapCount(Map<String, dynamic> snapshot) {
    final rows = (snapshot['data'] as Map)['elements'] as List;
    final text =
        (rows.cast<Map>().firstWhere(
              (row) => row['key'] == 'tap_result',
            )['text'])
            as String;
    return int.parse(text.split(':').last.trim());
  }

  try {
    // Test-only handler uses the same daemon/IPC/session/adapter as production.
    await cli(['connect', uri], testCommand: true);
    // Verify rejected pre-connect sessions do not remain in session list or daemon lifetime.
    await cli(['connect', uri], session: 'conflict', expected: 3);
    await cli(['connect', 'not-a-uri'], session: 'invalid', expected: 2);
    final listing = await cli(['session', 'list']);
    final sessions = (listing['data'] as Map)['sessions'] as List;
    if (sessions.length != 1 || (sessions.single as Map)['name'] != 'sim') {
      throw StateError('Rejected connection left a session reservation');
    }
    final before = await cli(['snapshot']);
    final rows = (before['data'] as Map)['elements'] as List;
    final ref =
        rows.cast<Map>().firstWhere((row) => row['key'] == 'tap_button')['ref']
            as String;
    await cli(['verify-tap', ref], testCommand: true);
    final show = await cli(['session', 'show']);
    if ((show['data'] as Map)['snapshotValid'] != false) {
      throw StateError('Refs were not invalidated');
    }
    final stale = await cli(
      ['verify-tap', ref],
      testCommand: true,
      expected: 4,
    );
    if ((stale['error'] as Map)['code'] != 'STALE_REF') {
      throw StateError('Stale ref was not rejected');
    }
    final after = await cli(['snapshot']);
    if (tapCount(after) != tapCount(before) + 1) {
      throw StateError('Tap count did not increase exactly once');
    }
    await cli(['close']);
    final shutdownDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (File(p.join(runtime.path, 'daemon.json')).existsSync()) {
      if (DateTime.now().isAfter(shutdownDeadline)) {
        throw StateError('Daemon did not clean up after last close');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Do not restore connections or observations after restart.
    await cli(['connect', uri]);
    final reconnected = await cli(['session', 'show']);
    if ((reconnected['data'] as Map)['snapshotValid'] != false) {
      throw StateError('Snapshot was restored');
    }
    await cli(['close']);
    final output =
        Platform.environment['MARIONETTE_TEST_EVIDENCE'] ??
        '/tmp/mra-core-evidence.json';
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    stdout.writeln(
      'PASS: separate CLI connect/snapshot/action/stale-ref/reconnect; tap count ${tapCount(before)} -> ${tapCount(after)}',
    );
    stdout.writeln('Sanitized evidence: $output');
  } finally {
    await cli(['close']);
    // Wait for daemon file cleanup that happens after the final response.
    for (
      var i = 0;
      i < 100 && File(p.join(runtime.path, 'daemon.json')).existsSync();
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await runtime.delete(recursive: true);
  }
}
