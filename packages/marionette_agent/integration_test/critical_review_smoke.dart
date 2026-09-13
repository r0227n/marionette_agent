import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A fresh example app is required. The caller owns the Simulator and runner.
Future<void> main() async {
  final env = Platform.environment;
  final private = Directory(env['MARIONETTE_TEST_PRIVATE']!).absolute;
  final uri = File(env['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final device = env['MARIONETTE_TEST_DEVICE']!;
  final runtime = p.join(private.path, 'runtime');
  final evidence = await Directory(p.join(private.path, 'evidence'))
      .createTemp('review-');
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final script = p.join(root, 'bin/marionette_agent.dart');
  final records = <Map<String, Object?>>[];
  final checks = <String>[];
  void check(bool condition, String description) {
    if (!condition) throw StateError(description);
    checks.add(description);
  }

  Future<Map<String, dynamic>> cli(
    List<String> args, {
    int expected = 0,
    Map<String, String> environment = const {},
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        script,
        '--json',
        '--session',
        'critical',
        '--timeout',
        '30000',
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime, ...environment},
    );
    final output = result.stdout as String;
    final diagnostics = result.stderr as String;
    records.add({
      'args': args.map((value) => value == uri ? '<VM_URI>' : value).toList(),
      'environment': environment,
      'exitCode': result.exitCode,
      'stdout': output.replaceAll(uri, '<VM_URI>'),
      'stderr': diagnostics.replaceAll(uri, '<VM_URI>'),
    });
    check(
      !output.contains(uri) && !diagnostics.contains(uri),
      '${args.first}: URI is private',
    );
    check(
      result.exitCode == expected,
      '${args.first}: expected $expected, got ${result.exitCode}',
    );
    final envelope = jsonDecode(output) as Map<String, dynamic>;
    return (envelope[expected == 0 ? 'data' : 'error'] as Map)
        .cast<String, dynamic>();
  }

  Map row(Map snapshot, String key) => (snapshot['elements'] as List)
      .cast<Map>()
      .singleWhere((row) => row['key'] == key);
  Future<void> textIs(String key, String value) async {
    check(
      (await cli(['get', 'text', '--key', key]))['text'] == value,
      '$key = $value',
    );
  }

  String? failure;
  try {
    await cli(['--help']);
    await cli(['--version']);
    await cli(['doctor', '--quick']);
    await cli(['workflow', 'schema', 'tap']);
    await cli(['connect', uri]);
    final initial = await cli(['snapshot']);
    final ref = row(initial, 'tap_button')['ref'] as String;
    await cli(['tap', ref]);
    check(
      (await cli(['tap', ref], expected: 4))['code'] == 'STALE_REF',
      'Old refs are refused',
    );
    await textIs('tap_result', 'Tap count: 1');
    await cli(['find', 'key', 'text_input', 'fill', 'reviewed']);
    check(
      (await cli(['get', 'value', '--key', 'text_input']))['value'] ==
          'reviewed',
      'Find fill reaches the selected field',
    );
    await cli(['tap', '--key', 'tap_result']);
    await cli(['wait', '300']);
    await cli(['screenshot', p.join(evidence.path, 'controls.png')]);
    await cli([
      'record',
      'start',
      p.join(evidence.path, 'gestures.mp4'),
      '--platform',
      'ios',
      '--device',
      device,
    ]);
    await cli(['swipe', '--key', 'page_view', 'left', '--distance', '250']);
    await cli(['wait', '500']);
    await textIs('page_result', 'Current page: 2');
    await cli(['tap', '--key', 'advanced_tab']);
    await cli(['find', 'label', 'Editable value', '--exact', 'focus']);
    await cli([
      'find',
      'placeholder',
      'Type here',
      '--exact',
      'type',
      'reviewed',
    ]);
    check(
      (await cli(['get', 'value', '--key', 'advanced_input']))['value'] ==
          'reviewed',
      'Find type preserves the selected field',
    );
    await cli(['focus', '--key', 'advanced_focus']);
    await cli(['wait', '500']);
    await cli([
      'screenshot',
      '--key',
      'advanced_input',
      p.join(evidence.path, 'input.png'),
    ]);
    await cli(['scrollintoview', '--key', 'advanced_drag']);
    await cli(['wait', '300']);
    final beforeDrag = await cli(['snapshot']);
    await cli([
      'drag',
      row(beforeDrag, 'advanced_drag')['ref'] as String,
      row(beforeDrag, 'advanced_drop')['ref'] as String,
    ]);
    await textIs('drop_result', 'Drop: item');
    await cli(['scrollintoview', '--key', 'advanced_checkbox']);
    await cli(['wait', '300']);
    final baseline = await cli(['snapshot']);
    final baselinePath = p.join(evidence.path, 'baseline.json');
    await File(baselinePath).writeAsString(jsonEncode(baseline));
    check(
      (await cli([
            'diff',
            'snapshot',
            '--baseline',
            baselinePath,
          ]))['changed'] ==
          false,
      'Diff ignores ref generations',
    );
    final batchPath = p.join(evidence.path, 'batch.json');
    await File(batchPath).writeAsString(
      jsonEncode([
        ['find', 'key', 'advanced_checkbox', 'check'],
        ['wait', '200'],
        ['is', 'checked', '--key', 'advanced_checkbox'],
        ['logs'],
      ]),
    );
    final batch = await cli(
      ['batch', batchPath],
      environment: {
        'MARIONETTE_AGENT_SESSION': '',
        'MARIONETTE_AGENT_TIMEOUT_MS': 'invalid',
      },
    );
    check(
      batch['completed'] == 4 && batch['results'][2]['data']['value'] == true,
      'Batch inherits explicit options over invalid environment',
    );
    check(
      (await cli([
            'diff',
            'snapshot',
            '--baseline',
            baselinePath,
          ]))['changed'] ==
          true,
      'Diff detects the checked state',
    );
    await cli(['screenshot', p.join(evidence.path, 'advanced.png')]);
    await cli(['record', 'stop']);
    final state = p.join(private.path, 'connection.json');
    await cli(['state', 'save', state]);
    await cli(['close']);
    await cli(['state', 'load', state]);
    await cli(['snapshot']);
    await File(state).delete();
  } catch (error) {
    failure = '$error'.replaceAll(uri, '<VM_URI>');
    rethrow;
  } finally {
    await cli(['close']);
    for (
      var i = 0;
      i < 100 && File(p.join(runtime, 'daemon.json')).existsSync();
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    check(!File(p.join(runtime, 'daemon.json')).existsSync(), 'Daemon stopped');
    await File(p.join(evidence.path, 'results.json')).writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'checks': checks, 'calls': records, 'failure': failure}),
    );
    stdout.writeln(
      'Evidence: ${evidence.path}; ${records.length} calls; ${failure == null ? 'PASS' : 'FAIL'}',
    );
  }
}
