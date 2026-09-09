import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'support/evidence.dart';

/// Two real Flutter instances; a TCP relay lets us cut only alpha's VM Service
/// connection without terminating either app or replacing the real backend.
Future<void> main() async {
  final first = Uri.parse(
    File(Platform.environment['MARIONETTE_TEST_VM_URI_FILE']!)
        .readAsStringSync()
        .trim(),
  );
  final second = File(Platform.environment['MARIONETTE_TEST_SECOND_URI_FILE']!)
      .readAsStringSync()
      .trim();
  final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>{};
  relay.listen((client) async {
    sockets.add(client);
    try {
      final upstream = await Socket.connect(first.host, first.port);
      sockets.add(upstream);
      void close() {
        client.destroy();
        upstream.destroy();
        sockets.remove(client);
        sockets.remove(upstream);
      }

      client.listen(upstream.add, onDone: close, onError: (_) => close());
      upstream.listen(client.add, onDone: close, onError: (_) => close());
    } catch (_) {
      client.destroy();
      sockets.remove(client);
    }
  });
  final alphaUri = first
      .replace(host: '127.0.0.1', port: relay.port)
      .toString();
  final runtime = await Directory('/tmp').createTemp('mra-two-apps-');
  final output = p.absolute(
    Platform.environment['MARIONETTE_TEST_EVIDENCE'] ??
        '/tmp/mra-two-apps-results.json',
  );
  final artifacts = await createEvidenceDirectory(output, 'two-app-screens');
  final cliPath = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin',
    'marionette_agent.dart',
  );
  final records = <Object>[];
  Future<Map<String, dynamic>> cli(
    String session,
    List<String> args, {
    int expected = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliPath, '--json', '--session', session, ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    final diagnostics = result.stderr as String;
    if ([first.toString(), second, alphaUri].any(diagnostics.contains)) {
      throw StateError('URI leaked');
    }
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final command = args.first == 'connect'
        ? 'connect <VM_URI>'
        : args.join(' ');
    records.add({
      'session': session,
      'command': command,
      'exitCode': result.exitCode,
      'result': json,
      'diagnostics': diagnostics,
    });
    if (result.exitCode != expected) {
      throw StateError(
        '$session $command expected $expected, got ${result.exitCode}: ${json['error']}',
      );
    }
    return json;
  }

  Map row(Map snapshot, String key) =>
      ((snapshot['data'] as Map)['elements'] as List).cast<Map>().firstWhere(
        (e) => e['key'] == key,
      );
  int count(Map snapshot) => int.parse(
    (row(snapshot, 'tap_result')['text'] as String).split(':').last.trim(),
  );
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    await cli('alpha', ['connect', alphaUri]);
    await cli('beta', ['connect', second]);
    await cli('conflict', ['connect', alphaUri], expected: 3);
    final list = await cli('alpha', ['session', 'list']);
    check(
      ((list['data'] as Map)['sessions'] as List).length == 2,
      'Session ownership failed',
    );
    // Restore the top after features_smoke, while leaving the app state intact.
    await cli('alpha', [
      'scroll',
      '--key',
      'operation_scroll_area',
      'down',
      '--distance',
      '600',
    ]);
    var a = await cli('alpha', ['snapshot']);
    final b = await cli('beta', ['snapshot']);
    final betaRef = row(b, 'tap_button')['ref'] as String;
    final alphaRef = row(a, 'tap_button')['ref'] as String;
    final beforeA = count(a), beforeB = count(b);
    await cli('beta', ['tap', alphaRef], expected: 4);
    final pageRef = row(a, 'page_view')['ref'] as String;
    await cli('alpha', ['swipe', pageRef, 'left', '--distance', '300']);
    await cli('alpha', ['swipe', pageRef, 'left'], expected: 4);
    a = await cli('alpha', ['snapshot']);
    check(
      row(a, 'page_result')['text'] == 'Current page: 2',
      'PageView did not advance',
    );
    final bounds = row(a, 'page_view')['bounds'] as Map;
    final y = '${(bounds['y'] as num) + (bounds['height'] as num) / 2}';
    await cli('alpha', [
      'swipe',
      '--start-x',
      '100',
      '--start-y',
      y,
      '--end-x',
      '350',
      '--end-y',
      y,
    ]);
    a = await cli('alpha', ['snapshot']);
    check(
      row(a, 'page_result')['text'] == 'Current page: 1',
      'Coordinate swipe did not return',
    );
    await cli('alpha', [
      'swipe',
      '--key',
      'dismissible_item',
      'left',
      '--distance',
      '200',
    ]);
    a = await cli('alpha', ['snapshot']);
    check(
      row(a, 'dismiss_result')['text'] == 'Item dismissed',
      'Dismissible not dismissed',
    );
    await cli('beta', ['tap', betaRef]);
    final betaAfter = await cli('beta', ['snapshot']);
    check(
      count(betaAfter) == beforeB + 1,
      'Alpha actions invalidated beta refs',
    );
    check(
      row(betaAfter, 'page_result')['text'] == 'Current page: 1',
      'Alpha swipe affected beta',
    );
    // Smaller Simulators place Dismissible below the initial viewport.
    await cli('beta', [
      'scroll',
      '--key',
      'operation_scroll_area',
      'up',
      '--distance',
      '200',
    ]);
    row(await cli('beta', ['snapshot']), 'dismissible_item');
    await cli('beta', [
      'scroll',
      '--key',
      'operation_scroll_area',
      'down',
      '--distance',
      '600',
    ]);
    final old = row(a, 'tap_button')['ref'] as String;
    await cli('alpha', ['close']);
    await cli('beta', ['tap', '--key', 'tap_button']);
    await cli('alpha', ['connect', alphaUri]);
    final show = await cli('alpha', ['session', 'show']);
    check(
      (show['data'] as Map)['snapshotValid'] == false,
      'Reconnect restored refs',
    );
    await cli('alpha', ['tap', old], expected: 4);
    a = await cli('alpha', ['snapshot']);
    check(count(a) == beforeA, 'Closing alpha changed app state');
    // Cut a real established VM Service transport; beta remains connected.
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    sockets.clear();
    final disconnected = await cli('alpha', ['session', 'show']);
    check(
      (disconnected['data'] as Map)['state'] == 'disconnected',
      'Transport loss not detected',
    );
    await cli('alpha', ['tap', '--key', 'tap_button'], expected: 3);
    await cli('beta', ['tap', '--key', 'tap_button']);
    await cli('alpha', ['connect', alphaUri]);
    a = await cli('alpha', ['snapshot']);
    await cli('alpha', ['tap', row(a, 'tap_button')['ref'] as String]);
    a = await cli('alpha', ['snapshot']);
    check(count(a) == beforeA + 1, 'Alpha did not recover');
    await Future.wait([
      cli('beta', ['tap', '--key', 'tap_button']),
      cli('beta', ['tap', '--key', 'tap_button']),
    ]);
    final finalBeta = await cli('beta', ['snapshot']);
    check(
      count(finalBeta) == beforeB + 5,
      'Concurrent requests lost/repeated an action',
    );
    await cli('alpha', ['screenshot', p.join(artifacts.path, 'alpha.png')]);
    await cli('beta', ['screenshot', p.join(artifacts.path, 'beta.png')]);
    stdout.writeln(
      'PASS: two real apps, refs/state isolation, close/reconnect, transport loss/recovery, parallel calls and both swipe modes',
    );
  } finally {
    await cli('alpha', ['close']);
    await cli('beta', ['close']);
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await relay.close();
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
