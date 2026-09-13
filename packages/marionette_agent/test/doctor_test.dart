import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/backend/doctor_probe.dart';
import 'package:marionette_agent/src/cli/doctor.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mra9-');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
  });
  Future<ProcessResult> process(
    String exe,
    List<String> args,
    DateTime end,
  ) async => ProcessResult(
    0,
    0,
    exe.endsWith('/id')
        ? '501'
        : exe.endsWith('/stat')
        ? '501:700'
        : jsonEncode({
            'devices': {
              'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                {
                  'isAvailable': true,
                  'name': 'Fixture',
                  'udid': 'fixture',
                  'state': 'Shutdown',
                },
              ],
            },
          }),
    '',
  );
  Doctor doctor({
    String? runtime,
    Future<Json> Function(String, DateTime)? probe,
    String? sdk,
  }) => Doctor(
    os: 'macos',
    dartVersion: sdk ?? '3.13.2',
    runtimePath: runtime ?? dir.path,
    process: process,
    probe: probe,
  );
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));
  Json check(Json result, String id) =>
      (result['checks'] as List).cast<Json>().singleWhere((c) => c['id'] == id);

  test('parser is sessionless and accepts only explicit probe option', () {
    expect(CliParser().parse(['doctor']).resultSession, isNull);
    expect(
      CliParser().parse([
        'doctor',
        '--probe-uri',
        'http://localhost/token',
      ]).params['probeUri'],
      'http://localhost/token',
    );
    expect(
      () => CliParser().parse(['doctor', 'http://localhost']),
      throwsA(isA<AgentError>()),
    );
  });
  test('doctor argument errors remain sessionless in output recovery', () {
    for (final args in [
      ['doctor', '--bad', '--json'],
      ['doctor', 'unexpected', '--json'],
      ['doctor', '--timeout', '0', '--json'],
      ['doctor', '--probe-uri'],
    ]) {
      String? session = 'not-called';
      expect(
        () => CliParser().parse(args, onOutput: (name, _) => session = name),
        throwsA(isA<AgentError>()),
      );
      expect(session, isNull);
    }
  });
  test('absent runtime stays absent and default doctor never probes', () async {
    final missing = '${dir.path}/absent';
    final result = await doctor(
      runtime: missing,
      probe: (_, _) => throw StateError('must not probe'),
    ).run(deadline());
    expect(check(result, 'runtime.directory')['status'], 'skipped');
    expect(check(result, 'daemon.ipc')['status'], 'skipped');
    expect(check(result, 'probe.vmService')['status'], 'skipped');
    expect(result['exitCode'], 0);
    expect(Directory(missing).existsSync(), false);
  });
  test('unsupported SDK and long/nonabsolute runtime fail', () async {
    final result = await doctor(
      runtime: 'relative',
      sdk: '4.0.0',
    ).run(deadline());
    expect(check(result, 'host.dart')['status'], 'failure');
    expect(check(result, 'runtime.socketPath')['status'], 'failure');
    expect(result['exitCode'], 1);
    final long = await doctor(runtime: '/${List.filled(81, 'x').join()}')
        .run(deadline());
    expect(check(long, 'runtime.socketPath')['status'], 'failure');
  });
  test(
    'unsafe permission blocks socket inspection and preserves files',
    () async {
      final sentinel = File('${dir.path}/daemon.json')
        ..writeAsString('unchanged');
      final result = await Doctor(
        os: 'macos',
        dartVersion: '3.13.2',
        runtimePath: dir.path,
        process: (exe, args, end) async => exe.endsWith('/stat')
            ? ProcessResult(0, 0, '502:755', '')
            : process(exe, args, end),
      ).run(deadline());
      expect(check(result, 'runtime.directory')['status'], 'failure');
      expect(check(result, 'daemon.ipc')['status'], 'skipped');
      expect(sentinel.readAsStringSync(), 'unchanged');
    },
  );
  for (final mode in ['compatible', 'mismatch', 'silent']) {
    test('passive IPC $mode sends no request and preserves socket', () async {
      final server = await ServerSocket.bind(
        InternetAddress('${dir.path}/s', type: InternetAddressType.unix),
        0,
      );
      final clients = <Socket>[];
      final received = <int>[];
      server.listen((socket) {
        clients.add(socket);
        socket.listen(received.addAll);
        if (mode != 'silent') {
          socket.write(
            '${jsonEncode({'protocolVersion': mode == 'compatible' ? protocolVersion : -1, 'ready': true})}\n',
          );
        }
      });
      try {
        final result = await doctor().run(deadline());
        expect(
          check(result, 'daemon.ipc')['status'],
          mode == 'compatible'
              ? 'success'
              : mode == 'mismatch'
              ? 'failure'
              : 'unknown',
        );
        expect(received, isEmpty);
        expect(
          FileSystemEntity.typeSync('${dir.path}/s'),
          isNot(FileSystemEntityType.notFound),
        );
      } finally {
        for (final socket in clients) {
          socket.destroy();
        }
        await server.close();
      }
    });
  }
  test('probe error and timeout remain distinct and redact secrets in both formats', () async {
    for (final error in [StateError('SECRET'), TimeoutException('SECRET')]) {
      final result = await doctor(probe: (_, _) async => throw error).run(
        deadline(),
        probeUri: 'http://user:SECRET@localhost/SECRET?auth=SECRET',
      );
      expect(
        check(result, 'probe.vmService')['status'],
        error is TimeoutException ? 'unknown' : 'failure',
      );
      for (final json in [true, false]) {
        expect(
          render(Result.success(null, result), json: json),
          isNot(contains('SECRET')),
        );
      }
    }
  });
  test(
    'exhausted deadline reports unknown without starting external work',
    () async {
      final result = await doctor().run(
        DateTime.now().subtract(const Duration(seconds: 1)),
        probeUri: 'http://localhost',
      );
      expect(check(result, 'probe.vmService')['status'], 'unknown');
      expect(result['exitCode'], 1);
    },
  );
  test('missing dependency metadata is unknown, mismatched pins fail', () async {
    final diagnostic = Doctor(
      os: 'macos',
      dartVersion: '3.13.2',
      runtimePath: dir.path,
      packageRoot: dir.uri,
      process: process,
    );
    expect(
      check(await diagnostic.run(deadline()), 'dependencies.fixed')['status'],
      'unknown',
    );
    File('${dir.path}/pubspec.yaml').writeAsString(
      'dependencies:\n  marionette_mcp: 0.6.0\n  image: 4.9.1\n  yaml: 3.1.4\n',
    );
    File('${dir.path}/pubspec.lock').writeAsString(
      'packages:\n  marionette_mcp: {version: 0.5.0}\n  image: {version: 4.9.1}\n  yaml: {version: 3.1.4}\n',
    );
    expect(
      check(await diagnostic.run(deadline()), 'dependencies.fixed')['status'],
      'failure',
    );
  });
  test('refused VM endpoint fails without exposing URI', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final result = await doctor().run(
      deadline(),
      probeUri: 'http://127.0.0.1:$port/SECRET',
    );
    expect(check(result, 'probe.vmService')['status'], 'failure');
    expect(jsonEncode(result), isNot(contains('SECRET')));
  });
  test('silent VM times out and closes its socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closed = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {}, onDone: closed.complete);
    });
    try {
      await expectLater(
        probeVmService(
          'http://127.0.0.1:${server.port}/SECRET',
          DateTime.now().add(const Duration(milliseconds: 200)),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await closed.future.timeout(const Duration(seconds: 2));
    } finally {
      await server.close(force: true);
    }
  });
  test('external check process is bounded by deadline', () async {
    final watch = Stopwatch()..start();
    await expectLater(
      runDiagnosticProcess('/bin/sleep', [
        '10',
      ], DateTime.now().add(const Duration(milliseconds: 100))),
      throwsA(isA<TimeoutException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
  for (final binding in [false, true]) {
    test(
      'real VM wire probe observes binding=$binding and releases connection',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final closed = Completer<void>();
        server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen(
            (message) {
              final call = jsonDecode(message as String) as Map;
              final result = switch (call['method']) {
                'getVersion' => {'type': 'Version', 'major': 4, 'minor': 0},
                'getVM' => {
                  'type': 'VM',
                  'isolates': [
                    {
                      'type': '@Isolate',
                      'id': 'isolates/1',
                      'name': 'main',
                      'number': '1',
                    },
                  ],
                },
                'getIsolate' => {
                  'type': 'Isolate',
                  'id': 'isolates/1',
                  'extensionRPCs': binding
                      ? [
                          'ext.flutter.marionette.getVersion',
                          'ext.flutter.marionette.tap',
                        ]
                      : <String>[],
                },
                _ => {'type': '_extensionType', 'version': '0.6.0'},
              };
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': call['id'],
                  'result': result,
                }),
              );
            },
            onDone: () {
              if (!closed.isCompleted) closed.complete();
            },
          );
        });
        try {
          final result = await probeVmService(
            'http://127.0.0.1:${server.port}/SECRET/',
            deadline(),
          );
          expect(result['bindingStatus'], binding ? 'observed' : 'unknown');
          expect(jsonEncode(result), isNot(contains('SECRET')));
          if (binding) {
            expect((result['bindings'] as List).single['version'], '0.6.0');
          }
          await closed.future.timeout(const Duration(seconds: 2));
        } finally {
          await server.close(force: true);
        }
      },
    );
  }
}
