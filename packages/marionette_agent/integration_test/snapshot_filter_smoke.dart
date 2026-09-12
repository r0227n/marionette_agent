import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/output/content.dart';
import 'package:path/path.dart' as p;

/// Product CLI verification against a fresh example, using caller-owned runtime.
Future<void> main() async {
  final env = Platform.environment;
  final uri = File(env['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final output = env['MARIONETTE_TEST_EVIDENCE']!;
  final evidence = Directory(p.dirname(output))..createSync(recursive: true);
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final records = <Object>[];
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<String> cli(
    List<String> args, {
    bool json = true,
    int expected = 0,
  }) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      p.join(root, 'bin/marionette_agent.dart'),
      '--session',
      'p1-issue-10',
      if (json) '--json',
      ...args,
    ]);
    final text = result.stdout as String;
    final diagnostics = result.stderr as String;
    check(!diagnostics.contains(uri) && !text.contains(uri), 'URI leak');
    records.add({
      'command': [
        'dart bin/marionette_agent.dart --session p1-issue-10',
        if (json) '--json',
        if (args.first == 'connect')
          'connect <private-uri>'
        else
          ...args.map(jsonEncode),
      ].join(' '),
      'expectedExit': expected,
      'exitCode': result.exitCode,
      'output': json ? jsonDecode(text) : text,
      'diagnostics': diagnostics,
    });
    check(result.exitCode == expected, 'Unexpected exit for ${args.first}');
    return text;
  }

  Future<Map> data(List<String> args) async =>
      (jsonDecode(await cli(args)) as Map)['data'] as Map;
  List<Map> rows(Map snapshot) => (snapshot['elements'] as List).cast<Map>();
  Map row(Map snapshot, String key) =>
      rows(snapshot).singleWhere((r) => r['key'] == key);
  String normalizeRef(String line) =>
      line.replaceAll(RegExp(r'@e[1-9][0-9]*'), '@REF');
  Map normalized(Map element) => {
    ...element,
    if (element.containsKey('ref')) 'ref': '@REF',
  };

  try {
    await cli(['connect', uri]);
    final full = await data(['snapshot']);
    check(
      row(full, 'tap_result')['text'] == 'Tap count: 0',
      'Fresh fixture required',
    );
    await cli(['screenshot', p.join(evidence.path, 'before.png')]);
    final filters = [
      ['key', 'tap_button'],
      ['text', 'Tap me'],
      ['text', 'Tap count: 0'],
      ['text', 'Filter label A'],
      ['type', 'SnapshotLabel'],
      ['identifier', 'snapshot_label_a'],
      ['type', 'Text'],
      ['identifier', 'missing-i10'],
      ['key', 'missing-i10'],
    ];
    // Include a display-only text type actually exposed by the fixed binding.
    const matchableTypes = {
      'Text',
      'RichText',
      'EditableText',
      'TextField',
      'TextFormField',
    };
    final unknown = rows(
      full,
    ).where((r) => r['text'] is String && !matchableTypes.contains(r['type']));
    check(
      unknown.length == 2 &&
          unknown.every(
            (r) => r['type'] == 'SnapshotLabel' && r['ref'] == null,
          ),
      'Display-only duplicate fixture must be observed without refs',
    );
    final collision = rows(full).where((r) => r['text'] == 'Filter label A');
    check(
      collision.length >= 2 && collision.every((r) => r['ref'] == null),
      'Unknown text collision must block unsafe refs',
    );
    records.add({
      'observedDisplayOnlyTextTypes': unknown
          .map((r) => r['type'])
          .toSet()
          .toList(),
    });
    for (final filter in filters) {
      final expected = rows(full)
          .where((r) => r[filter[0]] == filter[1])
          .toList();
      final selected = await data(['snapshot', '--${filter[0]}', filter[1]]);
      check(
        jsonEncode(rows(selected).map(normalized).toList()) ==
            jsonEncode(expected.map(normalized).toList()),
        'Filtered rows/ref safety differ from full observation',
      );
      check(
        selected['filter']['totalCount'] == rows(full).length &&
            selected['filter']['matchedCount'] == expected.length,
        'Incorrect filter counts',
      );
      final text = await cli([
        'snapshot',
        '--${filter[0]}',
        filter[1],
      ], json: false);
      check(
        text.contains(
          'matchedCount: ${expected.length}; totalCount: ${rows(full).length}',
        ),
        'Text counts',
      );
      final lines = const LineSplitter()
          .convert(text)
          .skip(2)
          .map(normalizeRef)
          .toList();
      check(
        jsonEncode(lines) ==
            jsonEncode(
              expected.map((r) => normalizeRef(snapshotLine(r))).toList(),
            ),
        'Text rows/ref safety differ from full observation',
      );
    }
    for (final json in [true, false]) {
      final limited = await cli([
        'snapshot',
        '--type',
        'Text',
        '--max-output',
        '1',
        '--content-boundaries',
      ], json: json);
      final count = rows(full).where((r) => r['type'] == 'Text').length;
      check(count > 1, 'Fixture must contain multiple Text observations');
      if (json) {
        final limitedData = jsonDecode(limited)['data'];
        check(
          limitedData['elements'].isEmpty &&
              limitedData['truncated'] == true &&
              limitedData['originalCount'] == count &&
              limitedData['omittedCount'] == count &&
              limitedData['filter']['matchedCount'] == count,
          'JSON limit ordering',
        );
      } else {
        check(
          limited.contains('Filter: type="Text"; matchedCount: $count') &&
              limited.contains(
                'Truncated: true; originalCount: $count; omittedCount: $count',
              ),
          'Text limit ordering',
        );
      }
      final empty = await cli([
        'snapshot',
        '--key',
        'missing-i10',
        '--max-output',
        '1',
      ], json: json);
      check(
        json
            ? jsonDecode(empty)['data']['truncated'] == false
            : empty.contains(
                'Truncated: false; originalCount: 0; omittedCount: 0',
              ),
        'Empty filter is not truncation',
      );
      await cli(
        ['snapshot', '--key', 'tap_button', '--type', 'Text'],
        json: json,
        expected: 2,
      );
    }
    final old = row(await data(['snapshot']), 'tap_button')['ref'] as String;
    await data(['snapshot', '--key', 'missing-i10']);
    final stale = jsonDecode(await cli(['tap', old], expected: 4));
    check(stale['error']['code'] == 'STALE_REF', 'Old ref was not rejected');
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 0',
      'Rejected ref changed counter',
    );
    await cli(['screenshot', p.join(evidence.path, 'after-stale-ref.png')]);
    final valid =
        row(
              await data([
                'snapshot',
                '--key',
                'tap_button',
                '--max-output',
                '10000',
              ]),
              'tap_button',
            )['ref']
            as String;
    await cli(['tap', valid]);
    final after = await data(['snapshot', '--key', 'tap_result']);
    check(
      row(after, 'tap_result')['text'] == 'Tap count: 1',
      'Valid visible ref did not increment counter',
    );
    await cli(['screenshot', p.join(evidence.path, 'after-valid-ref.png')]);
    final oldTextRef =
        row(await data(['snapshot']), 'tap_button')['ref'] as String;
    await cli(['snapshot', '--key', 'missing-i10'], json: false);
    final staleText = await cli(['tap', oldTextRef], json: false, expected: 4);
    check(staleText.contains('STALE_REF'), 'Text old-ref rejection');
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 1',
      'Text stale ref changed counter',
    );
    final selectedText = await cli([
      'snapshot',
      '--key',
      'tap_button',
    ], json: false);
    final textRef = RegExp(r'@e[1-9][0-9]*')
        .firstMatch(selectedText)!
        .group(0)!;
    await cli(['tap', textRef], json: false);
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 2',
      'Text visible ref did not operate',
    );
    await cli([
      'screenshot',
      p.join(evidence.path, 'after-valid-text-ref.png'),
    ]);
    records.add({
      'assertions': 'passed',
      'counterBefore': 0,
      'counterAfterStaleRef': 0,
      'counterAfterValidRef': 1,
      'counterAfterValidTextRef': 2,
    });
  } finally {
    try {
      await cli(['close']);
    } finally {
      File(
        output,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
    }
  }
  stdout.writeln(
    'Snapshot filter Simulator checks passed (${records.length} records).',
  );
}
