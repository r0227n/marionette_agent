import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Product CLI acceptance against the assigned running example. Private inputs
/// and output roots are supplied by the worker; raw URI is never recorded.
Future<void> main() async {
  final private = Platform.environment['MARIONETTE_TEST_PRIVATE_DIR']!;
  final runtime = p.join(private, 'runtime');
  final evidence = Directory(p.join(private, 'evidence'));
  final uri = File(p.join(private, 'vm-uri')).readAsStringSync().trim();
  final cliPath = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin/marionette_agent.dart',
  );
  final records = <Object>[];
  final secretPath = Uri.parse(uri).path;
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<String> call(
    List<String> args, {
    bool json = true,
    int expected = 0,
    String? directory,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliPath, '--session', 'p1-issue-9', if (json) '--json', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': directory ?? runtime},
    );
    final output = '${result.stdout}';
    final diagnostics = '${result.stderr}';
    for (final text in [output, diagnostics]) {
      require(
        !text.contains(uri) &&
            !text.contains('doctor-private-token') &&
            (secretPath.length < 4 || !text.contains(secretPath)),
        'Secret leaked; raw response withheld',
      );
    }
    final safeArgs = [...args];
    if (safeArgs.first == 'connect') safeArgs[1] = '<VM_URI>';
    final index = safeArgs.indexOf('--probe-uri');
    if (index >= 0) safeArgs[index + 1] = '<EXPLICIT_PROBE_URI>';
    records.add({
      'command':
          'dart bin/marionette_agent.dart --session p1-issue-9 ${json ? '--json ' : ''}${safeArgs.join(' ')}',
      'runtime': directory ?? runtime,
      'expectedExit': expected,
      'actualExit': result.exitCode,
      'stdout': output,
      'stderr': diagnostics,
    });
    require(
      result.exitCode == expected,
      'Unexpected exit for ${safeArgs.join(' ')}: ${result.exitCode}',
    );
    require(diagnostics.isEmpty, 'Unexpected diagnostic output');
    return output;
  }

  Future<Map> data(List<String> args) async =>
      (jsonDecode(await call(args)) as Map)['data'] as Map;
  Map row(Map snapshot, String key) => (snapshot['elements'] as List)
      .cast<Map>()
      .firstWhere((item) => item['key'] == key);
  Future<void> diagnostic(
    List<String> args,
    String id,
    String status, {
    int exit = 0,
    String? directory,
    bool unknownBinding = false,
  }) async {
    for (final json in [false, true]) {
      final output = await call(
        ['doctor', ...args],
        json: json,
        expected: exit,
        directory: directory,
      );
      if (json) {
        final body = jsonDecode(output) as Map;
        require(
          body['ok'] == true && body['session'] == null,
          'Doctor envelope',
        );
        final checks = (body['data']['checks'] as List).cast<Map>();
        final check = checks.singleWhere((item) => item['id'] == id);
        require(check['status'] == status, 'Unexpected $id status');
        if (unknownBinding) {
          require(
            check['details']['bindingStatus'] == 'unknown',
            'Unobserved binding must remain unknown',
          );
        }
      } else {
        require(output.contains('[$status] $id:'), 'Text diagnostic status');
      }
    }
  }

  final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final unobserved = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  silent.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((_) {});
  });
  unobserved.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((message) {
      final request = jsonDecode(message as String) as Map;
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': request['method'] == 'getVersion'
              ? {'type': 'Version', 'major': 4, 'minor': 0}
              : {'type': 'VM', 'isolates': <Object>[]},
        }),
      );
    });
  });
  final refused = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final refusedPort = refused.port;
  await refused.close(force: true);
  var connected = false;
  try {
    require(
      !Directory(runtime).existsSync(),
      'Acceptance requires a fresh runtime',
    );
    await diagnostic([], 'probe.vmService', 'skipped');
    require(!Directory(runtime).existsSync(), 'Doctor created runtime');
    for (final mode in ['mismatch', 'silent']) {
      final ipcDir = Directory(p.join(private, 'ipc-$mode'))..createSync();
      await Process.run('/bin/chmod', ['700', ipcDir.path]);
      final server = await ServerSocket.bind(
        InternetAddress('${ipcDir.path}/s', type: InternetAddressType.unix),
        0,
      );
      final clients = <Socket>[];
      var bytes = 0;
      server.listen((socket) {
        clients.add(socket);
        socket.listen((chunk) {
          bytes += chunk.length;
        });
        if (mode == 'mismatch') {
          socket.write('{"protocolVersion":-1,"ready":true}\n');
        }
      });
      try {
        await diagnostic(
          [],
          'daemon.ipc',
          mode == 'mismatch' ? 'failure' : 'unknown',
          exit: 1,
          directory: ipcDir.path,
        );
        require(bytes == 0, 'Doctor sent a daemon request');
        require(
          FileSystemEntity.typeSync('${ipcDir.path}/s') !=
              FileSystemEntityType.notFound,
          'Doctor removed socket',
        );
      } finally {
        for (final socket in clients) {
          socket.destroy();
        }
        await server.close();
      }
    }
    await data(['connect', uri]);
    connected = true;
    final initial = await data(['snapshot']);
    require(
      row(initial, 'tap_result')['text'] == 'Tap count: 0',
      'Example must be freshly launched',
    );
    await data(['screenshot', p.join(evidence.path, 'doctor-before.png')]);
    final probes = <(String, List<String>, String, int)>[
      ('successful', ['--probe-uri', uri], 'success', 0),
      (
        'refused',
        ['--probe-uri', 'http://127.0.0.1:$refusedPort/doctor-private-token'],
        'failure',
        1,
      ),
      (
        'timeout',
        [
          '--probe-uri',
          'http://127.0.0.1:${silent.port}/doctor-private-token',
          '--timeout',
          '2500',
        ],
        'unknown',
        1,
      ),
      (
        'unobserved',
        [
          '--probe-uri',
          'http://127.0.0.1:${unobserved.port}/doctor-private-token',
        ],
        'success',
        0,
      ),
    ];
    var count = 0;
    for (final (name, args, status, exit) in probes) {
      final snapshot = await data(['snapshot']);
      final ref = row(snapshot, 'tap_button')['ref'] as String;
      final sessionBefore = await data(['session', 'show']);
      final metadata = File('$runtime/daemon.json').readAsStringSync();
      final entries = Directory(
        runtime,
      ).listSync().map((file) => p.basename(file.path)).toList()..sort();
      await diagnostic([], 'probe.vmService', 'skipped');
      await diagnostic(
        args,
        'probe.vmService',
        status,
        exit: exit,
        unknownBinding: name == 'unobserved',
      );
      require(
        jsonEncode(await data(['session', 'show'])) ==
            jsonEncode(sessionBefore),
        'Probe changed session',
      );
      require(
        File('$runtime/daemon.json').readAsStringSync() == metadata,
        'Probe changed daemon metadata',
      );
      final afterEntries = Directory(
        runtime,
      ).listSync().map((file) => p.basename(file.path)).toList()..sort();
      require(
        jsonEncode(entries) == jsonEncode(afterEntries),
        'Probe changed runtime entries',
      );
      await data(['tap', ref]);
      count++;
      final after = await data(['snapshot']);
      require(
        row(after, 'tap_result')['text'] == 'Tap count: $count',
        'Saved ref did not increment counter after $name probe',
      );
      await data([
        'screenshot',
        p.join(evidence.path, 'doctor-after-$name.png'),
      ]);
      records.add({
        'scenario': name,
        'sameRef': ref,
        'sessionPreserved': true,
        'runtimePreserved': true,
        'expectedScreen': 'Tap count: $count',
        'actualScreenState': row(after, 'tap_result')['text'],
      });
    }
  } finally {
    if (connected) await data(['close']);
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await silent.close(force: true);
    await unobserved.close(force: true);
    File(p.join(evidence.path, 'doctor-results.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
  }
  require(
    !File('$runtime/daemon.json').existsSync(),
    'Daemon remained after close',
  );
  stdout.writeln(
    'Doctor acceptance passed; sanitized evidence: ${evidence.path}',
  );
}
