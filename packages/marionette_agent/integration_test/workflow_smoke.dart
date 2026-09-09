import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'support/evidence.dart';

/// Actual product CLI processes against the example app. URI is never evidence.
Future<void> main() async {
  final uri = File(Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final runtime = await Directory('/tmp').createTemp('mra-workflow-');
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final output = p.absolute(
    Platform.environment['MARIONETTE_TEST_EVIDENCE'] ??
        '/tmp/mra-workflow-results.json',
  );
  final screenshots = await createEvidenceDirectory(output, 'workflow-screens');
  final records = <Object>[];
  Future<Map> cli(List<String> args, {int expected = 0}) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        p.join(root, 'bin/marionette_agent.dart'),
        '--json',
        '--session',
        'workflow-demo',
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    if ((result.stderr as String).contains(uri)) {
      throw StateError('URI diagnostic leak');
    }
    final body = jsonDecode(result.stdout as String) as Map;
    final command = args.first == 'connect'
        ? 'connect <VM_URI>'
        : args.first == 'fill'
        ? 'fill <ref> <demo-text>'
        : args.join(' ');
    records.add({
      'command': command,
      'exitCode': result.exitCode,
      'result': body,
      'diagnostics': result.stderr,
    });
    if (result.exitCode != expected) {
      throw StateError(
        '$command expected $expected, got ${result.exitCode}: ${body['error']}',
      );
    }
    return body;
  }

  Map row(Map data, String key) =>
      (data['elements'] as List).cast<Map>().firstWhere((e) => e['key'] == key);
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  String example(String file) => p.join(root, 'examples/workflows', file);
  try {
    await cli(['workflow', 'schema', 'tap']);
    await cli(['workflow', 'validate', example('reach-controls.yaml')]);
    await cli(['workflow', 'validate', example('fill-input.json')]);
    await cli([
      'workflow',
      'validate',
      example('fill-input.json'),
      '--check-inputs',
    ], expected: 2);
    await cli([
      'workflow',
      'validate',
      example('fill-input.json'),
      '--inputs',
      example('inputs.example.json'),
    ]);
    await cli(['connect', uri]);
    final initial = await cli(['snapshot']);
    check(
      row(initial['data'], 'tap_result')['text'] == 'Tap count: 0',
      'Fixture must start fresh',
    );
    for (final format in ['yaml', 'json']) {
      final flow = await cli([
        'workflow',
        'run',
        example('reach-controls.$format'),
      ]);
      final data = flow['data'] as Map;
      check(
        data['completedSteps'] == 6 && data['requiresSnapshot'] == false,
        'Workflow completion',
      );
      final snapshot = data['finalSnapshot'] as Map;
      check(
        row(snapshot, 'page_result')['text'] == 'Current page: 2',
        'PageView did not reach page 2',
      );
      final ref = row(snapshot, 'text_input')['ref'] as String;
      await cli(['fill', ref, 'Workflow demo']);
      final observed = await cli(['snapshot']);
      check(
        row(observed['data'], 'fill_result')['text'] == '13 characters',
        'Separate CLI fill did not use final ref',
      );
      await cli(['screenshot', p.join(screenshots.path, '$format-filled.png')]);
    }
    final filled = await cli([
      'workflow',
      'run',
      example('fill-input.json'),
      '--inputs',
      example('inputs.example.json'),
    ]);
    check(
      row((filled['data'] as Map)['finalSnapshot'], 'fill_result')['text'] ==
          '13 characters',
      'Bound workflow fill',
    );
    final fail = await cli([
      'workflow',
      'run',
      example('stop-on-missing.json'),
    ], expected: 4);
    check(
      fail['error']['details']['completedSteps'] == 1 &&
          fail['error']['details']['stepIndex'] == 2 &&
          fail['error']['outcome'] == 'not_sent',
      'Failure progress',
    );
    final stopped = await cli(['snapshot']);
    check(
      row(stopped['data'], 'tap_result')['text'] == 'Tap count: 1',
      'Later tap was executed',
    );
    await cli(['screenshot', p.join(screenshots.path, 'stopped.png')]);
    await cli(['tap', '--key', 'about_tab']);
    await cli(['tap', '--key', 'controls_tab']);
    final reset = await cli(['snapshot']);
    check(
      row(reset['data'], 'fill_result')['text'] == 'Not edited',
      'Input label did not reset',
    );
    check(
      row(reset['data'], 'page_result')['text'] == 'Current page: 1',
      'Page label did not reset',
    );
    await cli(['screenshot', p.join(screenshots.path, 'tabs-reset.png')]);
  } finally {
    await cli(['close']);
    File(output)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (runtime.existsSync()) runtime.deleteSync(recursive: true);
  }
  stdout.writeln(
    'Workflow Simulator verification passed (${records.length} CLI calls). Evidence: $output',
  );
}
