import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Exercise the actual CLI against a fresh example app. The URI and raw runner
/// diagnostics stay private; the report contains only selected public results.
Future<void> main() async {
  final uriFile = Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!;
  final uri = (await File(uriFile).readAsString()).trim();
  final output = Directory(Platform.environment['MARIONETTE_TEST_EVIDENCE']!);
  await output.create(recursive: true);
  final runtime = await Directory('/tmp').createTemp('mra-i2-runtime-');
  await Process.run('chmod', ['700', runtime.path]);
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final records = <Map<String, Object?>>[];
  void check(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  Future<Object> cli(
    List<String> args, {
    bool json = true,
    int expected = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        p.join(root, 'bin/marionette_agent.dart'),
        '--session',
        'issue2',
        if (json) '--json',
        ...args,
      ],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final stdout = result.stdout as String;
    check(
      !stdout.contains(uri) && !(result.stderr as String).contains(uri),
      'URI was exposed',
    );
    final Object body = json ? jsonDecode(stdout) as Object : stdout;
    final safeArgs = args.first == 'connect'
        ? ['connect', '<private VM URI>', ...args.skip(2)]
        : args;
    records.add({
      'command': [if (json) '--json', ...safeArgs].join(' '),
      'expectedExit': expected,
      'actualExit': result.exitCode,
      'result': body,
    });
    check(
      result.exitCode == expected,
      '${safeArgs.first} exit code mismatch: ${result.exitCode}',
    );
    return body;
  }

  Future<Map> data(List<String> args) async =>
      (await cli(args) as Map)['data'] as Map;
  Map row(Map snapshot, String key) => (snapshot['elements'] as List)
      .cast<Map>()
      .firstWhere((row) => row['key'] == key);
  String boundary(String text, String source) {
    final nonce = RegExp('BEGIN UNTRUSTED $source ([0-9a-f]{32})')
        .firstMatch(text)!
        .group(1)!;
    check(
      text.contains('END UNTRUSTED $source $nonce'),
      'Unpaired content boundary',
    );
    return nonce;
  }

  final report = File(p.join(output.path, 'results.json'));
  try {
    await cli(['connect', uri, '--idle-timeout', '10s']);
    final before = await data(['snapshot']);
    check(
      row(before, 'tap_result')['text'] == 'Tap count: 0',
      'Restart the example before verification',
    );
    await cli(['screenshot', p.join(output.path, 'before.png')]);
    final firstText = await cli([
      'snapshot',
      '--content-boundaries',
      '--max-output',
      '300',
    ], json: false) as String;
    final secondText = await cli([
      'snapshot',
      '--content-boundaries',
      '--max-output',
      '300',
    ], json: false) as String;
    check(
      boundary(firstText, 'snapshot') != boundary(secondText, 'snapshot'),
      'Nonce reused',
    );
    check(
      firstText.startsWith('Snapshot ') &&
          firstText.contains('Truncated: true'),
      'Text limit missing',
    );
    final limited = await data([
      'snapshot',
      '--content-boundaries',
      '--max-output',
      '500',
    ]);
    check(
      limited['truncated'] == true && (limited['omittedCount'] as int) > 0,
      'JSON limit missing',
    );
    check(
      (limited['contentBoundary'] as Map)['source'] == 'snapshot',
      'JSON boundary source',
    );
    final all = await data(['snapshot']);
    final refs = (all['elements'] as List)
        .cast<Map>()
        .map((e) => e['ref'])
        .whereType<String>();
    final nextNumber =
        refs
            .map((r) => int.parse(r.substring(2)))
            .reduce((a, b) => a > b ? a : b) +
        1;
    final empty = await data(['snapshot', '--max-output', '1']);
    check(
      (empty['elements'] as List).isEmpty &&
          empty['originalCount'] == (all['elements'] as List).length,
      'Empty item budget',
    );
    final omitted = await cli(['tap', '@e$nextNumber'], expected: 4) as Map;
    check(
      (omitted['error'] as Map)['code'] == 'STALE_REF',
      'Guessed omitted ref was usable',
    );
    final mismatch = await cli([
      'tap',
      '--key',
      'tap_button',
      '--idle-timeout',
      '3m',
    ], expected: 2) as Map;
    check(
      (mismatch['error'] as Map)['outcome'] == 'not_sent',
      'Mismatch sent a mutation',
    );
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 0',
      'Rejected commands changed UI',
    );
    await cli(['tap', '--key', 'tap_button']);
    await cli(['fill', '--key', 'text_input', '日本😀']);
    await cli(['tap', '--key', 'tap_button']);
    final after = await data(['snapshot', '--content-boundaries']);
    check(
      row(after, 'tap_result')['text'] == 'Tap count: 2',
      'Tap result did not change exactly twice',
    );
    check(
      row(after, 'fill_result')['text'] == '4 characters',
      'Unicode fixture fill failed',
    );
    await cli(['screenshot', p.join(output.path, 'after.png')]);
    final logs = await data(['logs', '--content-boundaries']);
    check((logs['entries'] as List).isNotEmpty, 'No log fixture entries');
    check(
      (logs['contentBoundary'] as Map)['source'] == 'logs',
      'Log JSON boundary missing',
    );
    boundary(
      await cli(['logs', '--content-boundaries'], json: false) as String,
      'logs',
    );
    for (final json in [false, true]) {
      final result = await cli([
        'logs',
        '--content-boundaries',
        '--max-output',
        '1',
      ], json: json);
      if (json) {
        final limitedLogs = (result as Map)['data'] as Map;
        check(
          (limitedLogs['entries'] as List).isEmpty &&
              limitedLogs['truncated'] == true,
          'JSON logs not limited',
        );
      } else {
        check(
          (result as String).contains('Truncated: true'),
          'Text logs not limited',
        );
      }
    }
    final waitFile = File(p.join(output.path, 'wait-longer-than-idle.json'));
    await waitFile.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'name': 'idle-active',
        'steps': [
          {
            'id': 'wait',
            'action': 'wait',
            'target': {'key': 'never-present'},
            'state': 'exists',
            'timeoutMs': 12000,
            'pollIntervalMs': 100,
          },
        ],
      }),
    );
    final watch = Stopwatch()..start();
    final wait = await cli([
      'workflow',
      'run',
      waitFile.path,
      '--timeout',
      '20000',
    ], expected: 5) as Map;
    watch.stop();
    check(
      (wait['error'] as Map)['code'] == 'TIMEOUT' &&
          watch.elapsedMilliseconds >= 12000,
      'Idle interrupted active request',
    );
    check(
      File(p.join(runtime.path, 'daemon.json')).existsSync(),
      'Daemon exited during active request',
    );
    // Workflow's own timeout retires its connection. Explicit reconnect is safe.
    await cli(['connect', uri]);
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 2',
      'Long operation changed UI',
    );
    await Future<void>.delayed(const Duration(seconds: 11));
    check(
      !File(p.join(runtime.path, 'daemon.json')).existsSync(),
      'Idle daemon metadata remains',
    );
    final disconnected = await cli(['snapshot'], expected: 3) as Map;
    check(
      (disconnected['error'] as Map)['code'] == 'NOT_CONNECTED',
      'Missing explicit reconnect requirement',
    );
    await cli(['connect', uri]);
    final newSession = await data(['session', 'show']);
    check(newSession['snapshotValid'] == false, 'Idle shutdown retained refs');
    check(
      row(await data(['snapshot']), 'tap_result')['text'] == 'Tap count: 2',
      'App state lost after daemon shutdown',
    );
    await cli(['screenshot', p.join(output.path, 'reconnected.png')]);
    records.add({
      'check': 'active request lasted beyond 10s; daemon expired after 11s idle; explicit reconnect preserved app state',
      'actual': 'passed',
      'activeElapsedMs': watch.elapsedMilliseconds,
    });
  } finally {
    await cli(['close']);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (File(p.join(runtime.path, 'daemon.json')).existsSync() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    check(
      !File(p.join(runtime.path, 'daemon.json')).existsSync(),
      'Owned daemon did not close',
    );
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(records),
    );
  }
  stdout.writeln(
    'Safety options Simulator verification passed; ${records.length} sanitized records at ${report.path}',
  );
}
