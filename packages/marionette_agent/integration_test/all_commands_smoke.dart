import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

/// Real product CLI acceptance. See examples/workflows/README.md for setup.
/// Each run owns its runtime; the caller owns the device, app and Flutter runner.
Future<void> main() async {
  final env = Platform.environment;
  String required(String key) {
    final value = env[key];
    if (value == null || value.isEmpty) throw ArgumentError('Set $key');
    return value;
  }

  final platform = required('MARIONETTE_TEST_PLATFORM');
  if (!['ios', 'android'].contains(platform)) {
    throw ArgumentError('MARIONETTE_TEST_PLATFORM must be ios or android');
  }
  final device = required('MARIONETTE_TEST_DEVICE');
  final uri = File(required('MARIONETTE_TEST_VM_URI_FILE'))
      .readAsStringSync()
      .trim();
  if (uri.isEmpty) throw ArgumentError('VM URI file is empty');
  final parent = Directory(required('MARIONETTE_TEST_EVIDENCE')).absolute;
  await parent.create(recursive: true);
  final evidence = await parent.createTemp('$platform-');
  final runtime = await Directory('/tmp').createTemp('mra-all-cli-');
  await Process.run('chmod', ['700', runtime.path]);
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final script = p.join(root, 'bin/marionette_agent.dart');
  final workflow = p.join(root, 'examples/workflows/all-actions.yaml');
  final records = <Map<String, dynamic>>[];
  final checks = <String>[];
  String? failure;
  const sample = 'CLI verification';

  void check(bool condition, String description) {
    if (!condition) throw StateError(description);
    checks.add(description);
  }

  String redact(String value) => value.replaceAll(uri, '<VM_URI>');
  Future<Map<String, dynamic>> cli(
    List<String> args, {
    int expected = 0,
    String? error,
    bool global = false,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        script,
        '--json',
        if (!global) ...['--session', 'all-$platform'],
        '--timeout',
        args.first == 'wait' ? '5000' : '60000',
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final command = args.map(redact).toList();
    if (args.first == 'fill') command[command.length - 1] = '<fixture-input>';
    final output = result.stdout as String;
    final diagnostics = result.stderr as String;
    records.add({
      'command': command,
      'exitCode': result.exitCode,
      'expectedExitCode': expected,
      'stdout': redact(output),
      'stderr': redact(diagnostics).replaceAll(sample, '<fixture-input>'),
    });
    check(!output.contains(uri), 'No URI in ${args.first} output');
    check(
      !diagnostics.contains(uri) && !diagnostics.contains(sample),
      'No secrets in ${args.first} diagnostics',
    );
    check(
      result.exitCode == expected,
      '${command.join(' ')}: expected exit $expected, got ${result.exitCode}',
    );
    final body = jsonDecode(output) as Map<String, dynamic>;
    check(body['ok'] == (error == null), '${args.first}: result envelope');
    if (error != null) {
      check(body['error']['code'] == error, '${args.first}: $error');
      return body['error'] as Map<String, dynamic>;
    }
    return body['data'] as Map<String, dynamic>;
  }

  Map<String, dynamic> row(Map<String, dynamic> snapshot, String key) =>
      (snapshot['elements'] as List).cast<Map<String, dynamic>>().singleWhere(
        (element) => element['key'] == key,
      );
  Future<void> textIs(String key, String expected) async {
    final data = await cli(['get', 'text', '--key', key]);
    check(data['text'] == expected, '$key = $expected');
  }

  Future<void> capture(
    String name, {
    bool jpeg = false,
    bool annotate = false,
  }) async {
    final data = await cli([
      if (jpeg) ...[
        '--screenshot-format',
        'jpeg',
        '--screenshot-quality',
        '75',
      ],
      'screenshot',
      if (annotate) '--annotate',
      p.join(evidence.path, '$name.${jpeg ? 'jpg' : 'png'}'),
    ]);
    for (final path in data['paths'] as List) {
      final bytes = await File(path as String).readAsBytes();
      final decoded = jpeg ? image.decodeJpg(bytes) : image.decodePng(bytes);
      check(
        decoded != null && decoded.width > 0 && decoded.height > 0,
        '$name: image decodes',
      );
    }
  }

  try {
    stdout.writeln('Evidence: ${evidence.path}; runtime: ${runtime.path}');
    await cli(['--help'], global: true);
    await cli(['--version'], global: true);
    await cli(['doctor'], global: true);
    final probe = await cli(['doctor', '--probe-uri', uri], global: true);
    check(
      (probe['checks'] as List).any(
        (dynamic c) => c['id'] == 'probe.vmService' && c['status'] == 'success',
      ),
      'VM probe succeeds',
    );
    await cli(['workflow', 'schema'], global: true);
    for (final action in [
      'snapshot',
      'tap',
      'fill',
      'swipe',
      'scroll',
      'wait',
    ]) {
      final schema = await cli(['workflow', 'schema', action], global: true);
      check(schema['action'] == action, '$action schema');
    }
    final validated = await cli([
      'workflow',
      'validate',
      workflow,
      '--check-inputs',
    ], global: true);
    check(
      validated['stepCount'] == 16 && validated['inputsValidated'] == true,
      'All-actions YAML validates with inputs',
    );
    check(
      !File(p.join(runtime.path, 's')).existsSync(),
      'Local commands do not start daemon',
    );
    check(
      (await cli(['session', 'list'], global: true))['sessions'].isEmpty,
      'Initial session list is empty',
    );
    await cli(['snapshot'], expected: 3, error: 'NOT_CONNECTED');
    await cli(['connect', uri]);
    await cli(['connect', uri]);
    final sessions = await cli(['session', 'list'], global: true);
    check((sessions['sessions'] as List).length == 1, 'One connected session');
    await cli(['session', 'show']);
    var snapshot = await cli(['snapshot']);
    check(
      row(snapshot, 'tap_result')['text'] == 'Tap count: 0',
      'Fresh example app',
    );
    await capture('initial');
    await capture('initial-annotated', annotate: true);
    await capture('initial-jpeg', jpeg: true);
    final visible = await cli(['is', 'visible', '--key', 'tap_button']);
    check(
      visible['known'] == true && visible['value'] == true,
      'Tap button is visible',
    );
    final count = await cli(['get', 'count', '--type', 'Text']);
    check(
      count['count'] ==
          (snapshot['elements'] as List)
              .where((dynamic e) => e['type'] == 'Text')
              .length,
      'get count matches snapshot',
    );
    final missing = await cli([
      'get',
      'count',
      '--key',
      'missing-all-commands',
    ]);
    check(missing['count'] == 0, 'Missing count is zero');
    final buttonRef = row(snapshot, 'tap_button')['ref'] as String;
    final box = await cli(['get', 'box', buttonRef]);
    check(
      box['unit'] == 'flutter_logical_pixels' && box['bounds']['width'] > 0,
      'get box returns logical bounds',
    );
    await cli(['record', 'status']);
    final recording = await cli([
      'record',
      'start',
      p.join(evidence.path, 'operations.mp4'),
      '--platform',
      platform,
      '--device',
      device,
    ]);
    check(recording['recordingState'] == 'recording', 'Recording starts');
    await cli(['tap', buttonRef]);
    await textIs('tap_result', 'Tap count: 1');
    await cli(['tap', buttonRef], expected: 4, error: 'STALE_REF');
    await textIs('tap_result', 'Tap count: 1');
    final bounds = box['bounds'] as Map;
    await cli([
      'tap',
      '--x',
      '${bounds['x'] + bounds['width'] / 2}',
      '--y',
      '${bounds['y'] + bounds['height'] / 2}',
    ]);
    await textIs('tap_result', 'Tap count: 2');
    snapshot = await cli(['snapshot']);
    await cli(['fill', row(snapshot, 'text_input')['ref'] as String, sample]);
    await textIs('fill_result', '${sample.length} characters');
    await cli(['fill', '--key', 'text_input', 'abc']);
    await textIs('fill_result', '3 characters');
    await cli(['fill', '--key', 'text_input', '']);
    await textIs('fill_result', '0 characters');
    await cli(['fill', '--key', 'text_input', sample]);
    await textIs('fill_result', '${sample.length} characters');
    await cli(['tap', '--key', 'tap_result']);
    await cli(['swipe', '--key', 'page_view', 'left', '--distance', '250']);
    await cli(['wait', '--text', 'Current page: 2']);
    await textIs('page_result', 'Current page: 2');
    await capture('filled-page-two');
    final page =
        (await cli(['get', 'box', '--key', 'page_view']))['bounds'] as Map;
    final centerX = page['x'] + page['width'] / 2;
    final centerY = page['y'] + page['height'] / 2;
    // Stay inside the observed bounds and cross the page snapping threshold.
    final halfDistance = page['width'] * 0.4;
    await cli([
      'swipe',
      '--start-x',
      '${centerX - halfDistance}',
      '--start-y',
      '$centerY',
      '--end-x',
      '${centerX + halfDistance}',
      '--end-y',
      '$centerY',
    ]);
    await cli(['wait', '--text', 'Current page: 1']);
    await textIs('page_result', 'Current page: 1');
    await cli([
      'scroll',
      '--key',
      'operation_scroll_area',
      'up',
      '--distance',
      '400',
    ]);
    // Two planned gestures cover the fixture's long list on both phone sizes.
    await cli([
      'scroll',
      '--key',
      'operation_scroll_area',
      'up',
      '--distance',
      '150',
    ]);
    await cli(['wait', '--key', 'scroll_result']);
    await textIs('scroll_result', 'Bottom reached');
    await cli(['tap', '--key', 'log_button']);
    final logs = await cli(['logs']);
    check(
      (logs['entries'] as List).contains('manual log entry added'),
      'Manual log is observable',
    );
    await capture('scrolled');
    stdout.writeln('Standalone commands passed; running all-actions workflow.');
    final flow = await cli(['workflow', 'run', workflow]);
    check(
      flow['completedSteps'] == 16 && flow['requiresSnapshot'] == false,
      'All 16 workflow steps complete',
    );
    final finalSnapshot = flow['finalSnapshot'] as Map<String, dynamic>;
    check(
      row(finalSnapshot, 'scroll_result')['text'] == 'Bottom reached',
      'Workflow reaches bottom',
    );
    await cli(['tap', row(finalSnapshot, 'log_button')['ref'] as String]);
    await capture('workflow-bottom');
    await cli(['tap', '--key', 'about_tab']);
    await cli(['wait', '--key', 'about_content', '--state', 'exists']);
    await cli(['wait', '--key', 'operation_scroll_area', '--state', 'gone']);
    await capture('about');
    await cli(['tap', '--key', 'controls_tab']);
    await textIs('tap_result', 'Tap count: 3');
    await textIs('fill_result', 'Not edited');
    await textIs('page_result', 'Current page: 1');
    final filtered = await cli(['snapshot', '--key', 'tap_button']);
    check(
      (filtered['elements'] as List).length == 1,
      'Snapshot filter selects one element',
    );
    await cli(
      ['tap', '--key', 'missing-all-commands'],
      expected: 4,
      error: 'TARGET_NOT_FOUND',
    );
    await cli(
      ['tap', '--type', 'Text'],
      expected: 4,
      error: 'AMBIGUOUS_TARGET',
    );
    await cli(
      ['tap', '--identifier', 'tap_button'],
      expected: 6,
      error: 'UNSUPPORTED_CAPABILITY',
    );
    await textIs('tap_result', 'Tap count: 3');
    final active = await cli(['record', 'status']);
    check(
      active['recordingState'] == 'recording',
      'Recording survives workflow',
    );
    final stopped = await cli(['record', 'stop']);
    check(
      stopped['recordingState'] == 'stopped' && stopped['bytes'] > 0,
      'Recording finalized',
    );
    final stoppedAgain = await cli(['record', 'stop']);
    check(
      stoppedAgain['path'] == stopped['path'] &&
          stoppedAgain['bytes'] == stopped['bytes'],
      'record stop is idempotent',
    );
    await cli(['close']);
    await cli(['connect', uri]);
    await cli(['close', '--all'], global: true);
    check(
      (await cli(['session', 'list'], global: true))['sessions'].isEmpty,
      'close --all removes every owned session',
    );
    await cli(['snapshot'], expected: 3, error: 'NOT_CONNECTED');
  } catch (error) {
    failure = redact(error.toString());
  } finally {
    try {
      await cli(['close', '--all'], global: true);
      for (
        var i = 0;
        i < 100 &&
            (File(p.join(runtime.path, 's')).existsSync() ||
                File(p.join(runtime.path, 'daemon.json')).existsSync());
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      check(
        !File(p.join(runtime.path, 's')).existsSync() &&
            !File(p.join(runtime.path, 'daemon.json')).existsSync(),
        'Daemon stops and removes socket/metadata',
      );
    } catch (error) {
      failure ??= redact(error.toString());
    }
    await File(p.join(evidence.path, 'results.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': platform,
        'device': device,
        'runtime': runtime.path,
        'passed': failure == null,
        'failure': failure,
        'visualReview': 'pending: inspect PNG/JPEG and decoded video frames',
        'checks': checks,
        'records': records,
      }),
    );
  }
  if (failure != null) {
    stderr.writeln('FAIL: $failure. Evidence: ${evidence.path}');
    exitCode = 1;
  } else {
    stdout.writeln(
      'PASS: $platform, ${records.length} CLI calls. Inspect media: ${evidence.path}',
    );
  }
}
