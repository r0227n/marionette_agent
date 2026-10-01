import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:logging/logging.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/parser.dart' hide Invocation;
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import '../integration_test/support/evidence.dart';
import 'support/fake_backend.dart';

void main() {
  test('repeated verification runs save the same image name without clobbering evidence', () async {
    final root = await Directory('/tmp').createTemp('mra-evidence-');
    try {
      final report = '${root.path}/results.json';
      final first = await createEvidenceDirectory(report, 'screens');
      final second = await createEvidenceDirectory(report, 'screens');
      expect(first.path, isNot(second.path));
      final png = base64Encode(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      for (final directory in [first, second]) {
        await saveScreenshots(
          {
            'images': [png],
          },
          '${directory.path}/filled.png',
          DateTime.now().add(const Duration(seconds: 5)),
        );
      }
      expect(
        await File('${first.path}/filled.png').readAsBytes(),
        base64Decode(png),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('syntax errors retain output context without parsing literal values as options', () {
    for (final args in [
      ['--json', '--session', 'demo', 'tap', '--bogus'],
      ['workflow', 'run', 'flow.json', '--session=demo', '--bogus', '--json'],
      ['tap', '--key', '--json', '--session', 'demo', '--bogus'],
    ]) {
      String? session;
      bool? json;
      expect(
        () => CliParser().parse(
          args,
          onOutput: (s, j) {
            session = s;
            json = j;
          },
        ),
        throwsA(isA<AgentError>()),
      );
      expect(session, 'demo');
      expect(json, args.first != 'tap');
    }
  });
  test('timeout cannot overflow Duration or DateTime', () {
    for (final timeout in ['9223372036854775807', '9000000000000000']) {
      expect(
        () => CliParser().parse(['--timeout', timeout, 'snapshot']),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
        ),
      );
    }
  });
  test('malformed backend objects are backend errors, not local IO errors', () {
    for (final row in [
      null,
      {'bounds': []},
    ]) {
      expect(
        () => MarionetteBackend.decodeElements({
          'status': 'Success',
          'elements': [row],
        }),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR'),
        ),
      );
    }
  });
  test('unknown types cannot attest to the source of displayed text', () {
    final rows = MarionetteBackend.decodeElements({
      'status': 'Success',
      'elements': [
        {'type': 'CustomSemantics', 'text': 'Proceed'},
        {'type': 'Text', 'text': 'Proceed'},
      ],
    });
    expect(rows.first.text, 'Proceed');
    expect(rows.first.textMatchable, false);
    expect(rows.last.textMatchable, true);
  });
  test(
    'snapshot work scales linearly and lets other event-loop work advance',
    () async {
      final elements = List.generate(2000, (i) => _CountedElement('k$i'));
      final backend = FakeBackend()..elements = elements;
      final manager = SessionManager(() => backend, coreCommands());
      addTearDown(manager.dispose);
      await manager.handle(_request('connect', {'uri': 'http://localhost:1/'}));
      var eventRan = false;
      Timer.run(() => eventRan = true);
      final result = await manager.handle(_request('snapshot'));
      expect(result.exitCode, 0);
      expect((result.data!['elements'] as List).length, elements.length);
      expect(
        elements.fold<int>(0, (sum, e) => sum + e.reads),
        lessThan(elements.length * 20),
      );
      expect(eventRan, true);
    },
  );
  test(
    'completed collectors release late service events to diagnostics output',
    () async {
      final lines = <String>[];
      final entries = <DiagnosticEntry>[];
      final logging = configureDiagnosticLogging(lines.add);
      final events = StreamController<void>();
      late StreamSubscription<void> subscription;
      try {
        await captureDiagnostics(entries, () async {
          subscription = events.stream.listen(
            (_) => Logger('service').info('late event'),
          );
          Logger('service').info('connected');
        });
        events.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(entries.map((e) => e.message), ['connected']);
        expect(lines, ['[INFO] service: late event']);
      } finally {
        await subscription.cancel();
        await events.close();
        await logging.cancel();
      }
    },
  );
  test('text workflow failures retain step, completion and outcome', () {
    final text = render(
      Result.failure(
        'demo',
        const AgentError(
          'TARGET_NOT_FOUND',
          'Workflow step failed',
          details: {
            'workflow': 'demo',
            'progressKnown': true,
            'stepIndex': 4,
            'stepId': 'fill-name',
            'action': 'fill',
            'completedSteps': 3,
          },
        ),
      ),
      json: false,
    );
    expect(text, contains('3 steps completed'));
    expect(text, contains('step 4'));
    expect(text, contains('fill-name'));
    expect(text, contains('not_sent'));
  });
  test('FIFO input is rejected without waiting for a writer', () async {
    final dir = await Directory('/tmp').createTemp('mra-fifo-');
    final fifo = '${dir.path}/flow.json';
    expect((await Process.run('/usr/bin/mkfifo', [fifo])).exitCode, 0);
    final process = await Process.start(Platform.resolvedExecutable, [
      'bin/marionette_agent.dart',
      '--json',
      '--timeout',
      '100',
      'workflow',
      'validate',
      fifo,
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      expect(await process.exitCode.timeout(const Duration(seconds: 3)), 2);
      expect(
        (jsonDecode(await output) as Map)['error']['code'],
        'INVALID_ARGUMENT',
      );
      expect(await errors, '');
    } finally {
      process.kill();
      await process.exitCode;
      await dir.delete(recursive: true);
    }
  });
  test(
    'a stalled response cannot keep the daemon lifetime lock after close',
    () async {
      final dir = await Directory('/tmp').createTemp('mra-stall-');
      final runtime = await RuntimeDirectory.prepare(directory: dir.path);
      final backend = FakeBackend()..screenshots = ['x' * (8 * 1024 * 1024)];
      final server = DaemonServer(
        runtime,
        SessionManager(() => backend, coreCommands()),
      );
      final running = server.run();
      Socket? stalled;
      try {
        while (!File(runtime.metadata).existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final client = DaemonClient(runtime);
        expect(
          (await client.send(
            _request('connect', {'uri': 'http://localhost:1/'}),
          )).exitCode,
          0,
        );
        stalled = await Socket.connect(
          InternetAddress(runtime.socket, type: InternetAddressType.unix),
          0,
        );
        stalled.add(encodeFrame(_request('screenshot').toJson()));
        await stalled.flush();
        while (!backend.calls.contains('captureScreenshots')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect((await client.send(_request('close'))).exitCode, 0);
        await running.timeout(const Duration(seconds: 1));
        expect(File(runtime.metadata).existsSync(), false);
      } finally {
        stalled?.destroy();
        await server.close();
        await running;
        await dir.delete(recursive: true);
      }
    },
  );
}

Request _request(String command, [Json params = const {}]) => Request(
  requestId: command,
  session: 'demo',
  command: command,
  params: params,
  deadline: DateTime.now().add(const Duration(seconds: 5)),
);

class _CountedElement extends ElementInfo {
  _CountedElement(String key) : super(key: key, type: 'Text');
  int reads = 0;
  @override
  String? value(SelectorKind kind) {
    reads++;
    return super.value(kind);
  }
}
