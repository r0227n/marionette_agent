import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

/// Run against a freshly launched operation_confirmation. No URI or fill input
/// is written to diagnostics or evidence. Each call is a separate product CLI.
Future<void> main() async {
  final uri = File(Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final runtime = await Directory('/tmp').createTemp('mra-features-');
  final output = p.absolute(
    Platform.environment['MARIONETTE_TEST_EVIDENCE'] ??
        '/tmp/mra-features-results.json',
  );
  final artifacts = Directory(p.join(p.dirname(output), 'feature-screens'))
    ..createSync(recursive: true);
  final cliPath = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin',
    'marionette_agent.dart',
  );
  final records = <Object>[];
  const secret = 'private-fixture-input';
  Future<Map<String, dynamic>> cli(
    List<String> args, {
    int expected = 0,
  }) async {
    final process = await Process.run(
      Platform.resolvedExecutable,
      [cliPath, '--json', '--session', 'fixture', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final diagnostics = process.stderr as String;
    if (diagnostics.contains(uri) || diagnostics.contains(secret)) {
      throw StateError('Diagnostic information leak');
    }
    final result = jsonDecode(process.stdout as String) as Map<String, dynamic>;
    final command = args.first == 'connect'
        ? 'connect <VM_URI>'
        : args.first == 'fill'
        ? 'fill <target> <redacted-input>'
        : args.join(' ');
    records.add({
      'command': command,
      'exitCode': process.exitCode,
      'result': result,
      'diagnostics': diagnostics,
    });
    if (process.exitCode != expected) {
      throw StateError(
        '$command expected $expected, got ${process.exitCode}: ${result['error']}',
      );
    }
    return result;
  }

  Map row(Map snapshot, String key) =>
      ((snapshot['data'] as Map)['elements'] as List).cast<Map>().firstWhere(
        (e) => e['key'] == key,
      );
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    await cli(['tap', '--key', 'tap_button'], expected: 3);
    await cli(['connect', uri]);
    var s = await cli(['snapshot']);
    final target = row(s, 'tap_button')['ref'] as String;
    await cli(['tap', target]);
    await cli(['tap', target], expected: 4);
    s = await cli(['snapshot']);
    check(row(s, 'tap_result')['text'] == 'Tap count: 1', 'Tap failed');
    final b = row(s, 'tap_button')['bounds'] as Map;
    await cli([
      'tap',
      '--x',
      '${(b['x'] as num) + (b['width'] as num) / 2}',
      '--y',
      '${(b['y'] as num) + (b['height'] as num) / 2}',
    ]);
    s = await cli(['snapshot']);
    check(
      row(s, 'tap_result')['text'] == 'Tap count: 2',
      'Coordinate tap failed',
    );
    await cli(['tap', '--type', 'GestureDetector'], expected: 4);
    final input = row(s, 'text_input')['ref'] as String;
    await cli(['fill', input, secret]);
    s = await cli(['snapshot']);
    check(
      row(s, 'fill_result')['text'] == '${secret.length} characters',
      'Fill failed',
    );
    await cli(['fill', '--key', 'text_input', 'abc']);
    s = await cli(['snapshot']);
    check(
      row(s, 'fill_result')['text'] == '3 characters',
      'Replacement failed',
    );
    await cli(['fill', '--key', 'text_input', '']);
    s = await cli(['snapshot']);
    check(row(s, 'fill_result')['text'] == '0 characters', 'Clear failed');
    await cli(['fill', '--key', 'tap_button', secret], expected: 1);
    // Tap the existing result text, outside the text field, to dismiss keyboard.
    await cli(['tap', '--key', 'tap_result']);
    s = await cli(['snapshot']);
    final preserved = row(s, 'tap_button')['ref'] as String;
    final capture = await cli([
      'screenshot',
      p.join(artifacts.path, 'filled.png'),
    ]);
    final paths = (capture['data'] as Map)['paths'] as List;
    check(
      paths.every((path) => p.isAbsolute(path as String)),
      'Screenshot path not absolute',
    );
    final file = File(paths.single as String);
    final bytes = await file.readAsBytes();
    check(image.decodePng(bytes) != null, 'PNG cannot decode');
    await cli(['screenshot', file.path], expected: 1);
    check(
      base64Encode(await file.readAsBytes()) == base64Encode(bytes),
      'Existing PNG was modified',
    );
    final temporary = await cli(['screenshot']);
    final tempFile = File(
      ((temporary['data'] as Map)['paths'] as List).single as String,
    );
    check(
      image.decodePng(await tempFile.readAsBytes()) != null,
      'Temporary PNG invalid',
    );
    await tempFile.parent.delete(recursive: true);
    final logs = await cli(['logs']);
    check(
      ((logs['data'] as Map)['entries'] as List).contains('text input changed'),
      'Fixture logs absent',
    );
    await cli(['tap', preserved]);
    s = await cli(['snapshot']);
    check(
      row(s, 'tap_result')['text'] == 'Tap count: 3',
      'Read invalidated ref',
    );
    final before = row(s, 'scroll_item_1')['bounds'] as Map;
    await cli([
      'scroll',
      '--key',
      'operation_scroll_area',
      'up',
      '--distance',
      '400',
    ]);
    s = await cli(['snapshot']);
    final bottom = row(s, 'scroll_result');
    check(bottom['text'] == 'Bottom reached', 'Scroll did not reveal bottom');
    check(
      (bottom['bounds'] as Map)['y'] != before['y'],
      'Scroll state unchanged',
    );
    await cli(['tap', '--key', 'log_button']);
    final updatedLogs = await cli(['logs']);
    check(
      ((updatedLogs['data'] as Map)['entries'] as List).contains(
        'manual log entry added',
      ),
      'Log action missing',
    );
    await cli(['screenshot', p.join(artifacts.path, 'scrolled.png')]);
    stdout.writeln(
      'PASS: tap/ref/coordinates, fill replacement/clear/rejection, scroll, PNG, logs and ref preservation',
    );
  } finally {
    await cli(['close']);
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
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
