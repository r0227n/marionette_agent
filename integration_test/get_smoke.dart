import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Product CLI acceptance against a freshly launched example. URI stays private.
Future<void> main() async {
  final uri = File(Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final evidence = Directory(Platform.environment['MARIONETTE_TEST_EVIDENCE']!);
  evidence.createSync(recursive: true);
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final records = <Object>[];
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<Map> cli(
    List<String> args, {
    bool json = true,
    int expected = 0,
  }) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      p.join(root, 'bin/marionette_agent.dart'),
      '--session',
      'p1-issue-4',
      if (json) '--json',
      ...args,
    ]);
    check(!(result.stderr as String).contains(uri), 'URI diagnostic leak');
    final command = args.first == 'connect'
        ? 'connect <VM_URI>'
        : args.join(' ');
    records.add({
      'command': command,
      'format': json ? 'json' : 'text',
      'exitCode': result.exitCode,
      'stdout': result.stdout,
    });
    check(
      result.exitCode == expected,
      '$command exit ${result.exitCode}, expected $expected',
    );
    if (json) return jsonDecode(result.stdout as String) as Map;
    if (expected != 0) return {'output': result.stdout};
    final output = result.stdout as String;
    return {'data': jsonDecode(output) as Map};
  }

  Map row(Map snapshot, String key) => (snapshot['data']['elements'] as List)
      .cast<Map>()
      .firstWhere((e) => e['key'] == key);
  try {
    await cli(['connect', uri]);
    final initial = await cli(['snapshot']);
    check(
      row(initial, 'tap_result')['text'] == 'Tap count: 0',
      'Fresh fixture',
    );
    final button = row(initial, 'tap_button');
    final label = row(initial, 'tap_result');
    final elements = initial['data']['elements'] as List;
    for (final json in [true, false]) {
      final text = await cli(['get', 'text', label['ref']], json: json);
      check(text['data']['text'] == label['text'], 'Text matches snapshot');
      final box = await cli(['get', 'box', button['ref']], json: json);
      check(
        const DeepCollectionEquality().equals(
          box['data']['bounds'],
          button['bounds'],
        ),
        'Bounds match snapshot',
      );
      check(box['data']['unit'] == 'flutter_logical_pixels', 'Logical units');
      for (final target in [
        ['--key', 'missing-issue-4'],
        ['--key', 'tap_button'],
        ['--type', 'Text'],
      ]) {
        final count = await cli(['get', 'count', ...target], json: json);
        final kind = target.first.substring(2);
        final expected = elements.where((e) => e[kind] == target.last).length;
        check(
          count['data']['count'] == expected,
          'Count matches snapshot: $kind',
        );
        if (kind == 'type') check(expected > 1, 'Multiple Text fixture');
      }
      await cli(
        ['get', 'text', '--key', 'missing-issue-4'],
        json: json,
        expected: 4,
      );
      await cli(['get', 'box', '--type', 'Text'], json: json, expected: 4);
      await cli(['get', 'count', button['ref']], json: json, expected: 2);
      await cli(
        ['get', 'count', '--identifier', 'tap_button'],
        json: json,
        expected: 6,
      );
    }
    await cli(['screenshot', p.join(evidence.path, 'before.png')]);
    await cli(['tap', button['ref']]);
    for (final json in [true, false]) {
      await cli(['get', 'text', label['ref']], json: json, expected: 4);
      await cli(['get', 'box', button['ref']], json: json, expected: 4);
    }
    final after = await cli(['snapshot']);
    check(
      row(after, 'tap_result')['text'] == 'Tap count: 1',
      'Same ref tap changes count exactly once',
    );
    await cli(['screenshot', p.join(evidence.path, 'after.png')]);
  } finally {
    await cli(['close']);
    File(p.join(evidence.path, 'results.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
  }
  stdout.writeln(
    'Get Simulator verification passed (${records.length} CLI calls).',
  );
}
