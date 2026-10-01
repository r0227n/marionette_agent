import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:marionette_agent/src/protocol/protocol.dart' as protocol;

/// Source-only checkout -> AOT install -> owned tester -> observe/act -> shutdown.
/// No Simulator, native build, credentials, or raw app output in the report.
Future<void> main() async {
  final root = Directory.current.path;
  final private = Directory('/tmp').createTempSync('mra-release-');
  await Process.run('chmod', ['700', private.path]);
  final runtime = p.join(private.path, 'runtime');
  final destination = Directory(p.join(private.path, 'bin'))..createSync();
  final binary = p.join(destination.path, 'marionette-agent');
  final environment = {'MARIONETTE_AGENT_RUNTIME_DIR': runtime};
  final steps = <String>[];
  Future<Map<String, dynamic>> cli(
    List<String> args, {
    bool source = false,
  }) async {
    final result = await Process.run(
      source ? Platform.resolvedExecutable : binary,
      [
        if (source) p.join(root, 'bin/marionette_agent.dart'),
        '--json',
        '--session',
        'release',
        '--timeout',
        '180000',
        ...args,
      ],
      environment: environment,
    ).timeout(const Duration(minutes: 4));
    if (result.exitCode != 0) {
      throw StateError(
        'Release smoke ${args.first} failed (exit ${result.exitCode}); raw output withheld',
      );
    }
    final body = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError('Release smoke ${args.first} returned failure');
    }
    steps.add(args.first);
    return body;
  }

  void check(bool ok, String message) {
    if (!ok) throw StateError(message);
  }

  String text(Map<String, dynamic> snapshot, String key) =>
      ((snapshot['data'] as Map)['elements'] as List).cast<Map>().firstWhere(
            (row) => row['key'] == key,
          )['text']
          as String;
  try {
    await cli(['install', destination.path], source: true);
    final version = await cli(['--version']);
    check(
      version['data']['version'] == protocol.version,
      'Installed version mismatch',
    );
    final bundle = destination.listSync().whereType<Directory>().single;
    for (final name in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.txt']) {
      check(
        File(p.join(bundle.path, name)).readAsStringSync() ==
            File(name).readAsStringSync(),
        'Missing or changed $name',
      );
    }
    await cli(['launch', p.join(root, 'example'), '--platform', 'tester']);
    final before = await cli(['snapshot']);
    check(text(before, 'tap_result') == 'Tap count: 0', 'Fixture is not fresh');
    await cli(['tap', '--key', 'tap_button']);
    final afterTap = await cli(['snapshot']);
    check(
      text(afterTap, 'tap_result') == 'Tap count: 1',
      'Tap did not change app state',
    );
    await cli(['fill', '--key', 'text_input', 'hello']);
    final afterFill = await cli(['snapshot']);
    check(
      text(afterFill, 'fill_result') == '5 characters',
      'Fill did not change app state',
    );
    final screenshot = p.join(private.path, 'screen.png');
    await cli(['screenshot', screenshot]);
    check(File(screenshot).lengthSync() > 0, 'Screenshot empty');
    final evidence = Platform.environment['MARIONETTE_RELEASE_SCREENSHOT'];
    if (evidence != null) File(screenshot).copySync(evidence);
    await cli(['close']);
    for (
      var i = 0;
      i < 100 && File(p.join(runtime, 'daemon.json')).existsSync();
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    check(
      !File(p.join(runtime, 'daemon.json')).existsSync(),
      'Owned daemon did not stop',
    );
    stdout.writeln(
      'Release smoke passed: ${steps.join(' -> ')}; tap=1, input=5 characters, capture nonempty, daemon stopped.',
    );
  } finally {
    if (File(binary).existsSync() &&
        File(p.join(runtime, 'daemon.json')).existsSync()) {
      try {
        await cli(['close']);
      } catch (_) {
        /* Preserve original failure. */
      }
    }
    // Preserve recovery artifacts on failed cleanup, never discard a live runtime.
    if (!File(p.join(runtime, 'daemon.json')).existsSync()) {
      private.deleteSync(recursive: true);
    } else {
      stderr.writeln(
        'Cleanup incomplete; private recovery directory: ${private.path}',
      );
    }
  }
}
