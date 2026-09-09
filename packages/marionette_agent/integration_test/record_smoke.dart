import 'dart:convert';
import 'dart:io';

/// Run with MARIONETTE_RECORD_PLATFORM, MARIONETTE_RECORD_DEVICE,
/// MARIONETTE_TEST_VM_URI_FILE and MARIONETTE_RECORD_EVIDENCE.
/// Uses only product CLI calls; preserves no VM Service credentials in evidence.
Future<void> main() async {
  final env = Platform.environment;
  final platform = env['MARIONETTE_RECORD_PLATFORM']!;
  final device = env['MARIONETTE_RECORD_DEVICE']!;
  final output = await Directory(env['MARIONETTE_RECORD_EVIDENCE']!)
      .create(recursive: true);
  final uri = (await File(
    env['MARIONETTE_TEST_VM_URI_FILE']!,
  ).readAsString()).trim();
  final runtime = await Directory('/tmp').createTemp('mra-record-smoke-');
  await Process.run('chmod', ['700', runtime.path]);
  final script = File('bin/marionette_agent.dart').absolute.path;
  final records = <Object>[];
  final extension = platform == 'macos' ? 'mov' : 'mp4';
  Future<Map<String, dynamic>> cli(
    List<String> args, {
    bool secret = false,
    int expected = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        script,
        '--json',
        '--session',
        'record-smoke',
        '--timeout',
        '60000',
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final body = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    records.add({
      'command': secret ? ['connect', '<VM Service URI>'] : args,
      'exitCode': result.exitCode,
      'result': body,
    });
    if (result.exitCode != expected) {
      throw StateError('CLI ${args.first} failed: ${body['error']}');
    }
    return (body['data'] ?? <String, dynamic>{}) as Map<String, dynamic>;
  }

  try {
    final idle = await cli(['record', 'status']);
    if (idle['recordingState'] != 'idle') throw StateError('Expected idle');
    final started = await cli([
      'record',
      'start',
      '${output.path}/operations.$extension',
      '--platform',
      platform,
      '--device',
      device,
    ]);
    if (started['recordingState'] != 'recording') {
      throw StateError('Expected recording');
    }
    await cli(['connect', uri], secret: true);
    // Reset the fixture so repeated runs visibly demonstrate input/count changes.
    await cli(['tap', '--key', 'about_tab']);
    await cli(['tap', '--key', 'controls_tab']);
    final initial = await cli(['snapshot']);
    await cli(['screenshot', '${output.path}/before.png']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await cli(['tap', '--key', 'tap_button']);
    await cli(['tap', '--key', 'text_input']);
    await cli(['fill', '--key', 'text_input', 'record verification']);
    final after = await cli(['snapshot']);
    if (jsonEncode(initial['elements']) == jsonEncode(after['elements'])) {
      throw StateError('UI did not change');
    }
    if (!jsonEncode(after['elements']).contains('19 characters')) {
      throw StateError('Fill state did not update');
    }
    await cli(['screenshot', '${output.path}/after.png']);
    await Future<void>.delayed(const Duration(seconds: 1));
    final status = await cli(['record', 'status']);
    if (status['recordingState'] != 'recording') {
      throw StateError('Recording did not survive operations');
    }
    final stopped = await cli(['record', 'stop']);
    if (stopped['recordingState'] != 'stopped' ||
        (stopped['bytes'] as int) <= 0) {
      throw StateError('Video not finalized');
    }
    final again = await cli(['record', 'stop']);
    if (again['path'] != stopped['path'] ||
        again['bytes'] != stopped['bytes']) {
      throw StateError('Stop is not idempotent');
    }
    // A pre-existing destination must survive unchanged.
    final length = await File(stopped['path'] as String).length();
    await cli([
      'record',
      'start',
      stopped['path'] as String,
      '--platform',
      platform,
      '--device',
      device,
    ], expected: 1);
    if (await File(stopped['path'] as String).length() != length) {
      throw StateError('Existing video modified');
    }
    await cli([
      'record',
      'start',
      '${output.path}/close.$extension',
      '--platform',
      platform,
      '--device',
      device,
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
    final closed = await cli(['close']);
    if ((closed['recording'] as Map)['recordingState'] != 'stopped') {
      throw StateError('Close did not finalize');
    }
    stdout.writeln(
      'Recording CLI smoke passed: $platform; evidence: ${output.path}',
    );
  } finally {
    await cli(['close']);
    await File('${output.path}/results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    await runtime.delete(recursive: true);
  }
}
