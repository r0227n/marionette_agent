import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Product CLI acceptance on the caller-owned example/Simulator only.
Future<void> main() async {
  final uri = File(Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final evidence = Directory(Platform.environment['MARIONETTE_TEST_EVIDENCE']!);
  final runtime = Platform.environment['MARIONETTE_AGENT_RUNTIME_DIR']!;
  final unsupported =
      Platform.environment['MARIONETTE_TEST_UNSUPPORTED'] == 'true';
  final prefix = unsupported
      ? 'unsupported'
      : Platform.environment['MARIONETTE_TEST_PREFIX'] ?? 'portrait';
  final cliPath = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin/marionette_agent.dart',
  );
  final records = <Map<String, Object?>>[];
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  Future<Map<String, dynamic>?> cli(
    List<String> args, {
    bool json = true,
    String? error,
  }) async {
    final command = args.first == 'connect'
        ? 'connect <private URI>'
        : args.join(' ');
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliPath, '--session', 'p1-issue-11', if (json) '--json', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime},
    );
    final out = result.stdout as String;
    final err = result.stderr as String;
    check(!out.contains(uri) && !err.contains(uri), 'Private URI leaked');
    records.add({
      'command': '$command${json ? ' --json' : ''}',
      'exitCode': result.exitCode,
      'expected': error ?? 'success',
      'stdout': json ? jsonDecode(out) : out,
      'stderr': err,
    });
    final body = json ? jsonDecode(out) as Map<String, dynamic> : null;
    if (error == null) {
      check(result.exitCode == 0, '$command failed: $out');
    } else {
      check(
        result.exitCode != 0 &&
            (json
                ? body!['error']['code'] == error
                : out.startsWith('$error:')),
        '$command did not return $error: $out',
      );
    }
    return body;
  }

  String file(String name) => p.join(evidence.path, '$prefix-$name.png');
  Map row(Map snapshot, String key) => (snapshot['elements'] as List)
      .cast<Map>()
      .firstWhere((element) => element['key'] == key);
  try {
    await cli(['connect', uri]);
    for (final json in [true, false]) {
      await cli(
        ['screenshot', '--annotate', file('no-snapshot-$json')],
        json: json,
        error: 'STALE_REF',
      );
      check(
        !File(file('no-snapshot-$json')).existsSync(),
        'Stale output exists',
      );
    }
    await cli(['snapshot'], json: false);
    final snapshot = (await cli(['snapshot']))!['data'] as Map;
    final ref = row(snapshot, 'about_tab')['ref'] as String;
    await cli(['screenshot', file('original')]);
    final original = File(file('original')).readAsBytesSync();
    for (final json in [true, false]) {
      final output = file('annotated-$json');
      final result = await cli(
        ['screenshot', '--annotate', output],
        json: json,
        error: unsupported ? 'UNSUPPORTED_CAPABILITY' : null,
      );
      if (unsupported) {
        check(!File(output).existsSync(), 'Unsupported output exists');
      } else {
        check(File(output).existsSync(), 'Missing annotated output');
        if (json) {
          check(
            result!['data']['generation'] == snapshot['generation'],
            'Generation changed',
          );
          check(result['data']['annotationCount'] > 0, 'No annotations');
        }
      }
    }
    if (!unsupported) {
      for (final json in [true, false]) {
        await cli(
          ['screenshot', '--annotate', file('original')],
          json: json,
          error: 'IO_ERROR',
        );
        await cli(
          ['screenshot', '--annotate', file('annotated-true')],
          json: json,
          error: 'IO_ERROR',
        );
      }
    }
    check(
      const ListEquality<int>().equals(
        original,
        File(file('original')).readAsBytesSync(),
      ),
      'Original screenshot changed',
    );
    await cli(['tap', ref]);
    for (final json in [true, false]) {
      await cli(
        ['screenshot', '--annotate', file('stale-$json')],
        json: json,
        error: 'STALE_REF',
      );
      check(!File(file('stale-$json')).existsSync(), 'Stale output exists');
    }
    final after = (await cli(['snapshot']))!['data'] as Map;
    check(
      row(after, 'about_content')['text'] == 'Workflow fixture',
      'Ref tap did not reach About',
    );
    await cli(['screenshot', file('about-original')]);
    if (!unsupported) {
      await cli(['screenshot', '--annotate', file('about-annotated')]);
    }
    await cli(['tap', row(after, 'controls_tab')['ref'] as String]);
    final returned = (await cli(['snapshot']))!['data'] as Map;
    check(
      row(returned, 'tap_result')['text'] == 'Tap count: 0',
      'Unexpected tap state',
    );
    await cli(['screenshot', file('returned-controls')]);
  } finally {
    try {
      await cli(['close']);
    } finally {
      File(
        p.join(evidence.path, '$prefix-results.json'),
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
    }
  }
  stdout.writeln(
    'Passed $prefix: ${records.length} CLI calls; results in ${evidence.path}',
  );
}
