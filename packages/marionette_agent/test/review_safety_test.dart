import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

Request request(String command, [Json params = const {}]) => Request(
  requestId: command,
  session: 'review',
  command: command,
  params: params,
  deadline: DateTime.now().add(const Duration(seconds: 10)),
);
List<ElementInfo> elements({bool collision = true}) =>
    MarionetteBackend.decodeElements({
      'status': 'Success',
      'elements': [
        if (collision) {'type': 'CustomRichText', 'text': 'Save'},
        {'type': 'Text', 'text': 'Save'},
      ],
    });
void main() {
  test(
    'unknown text sources block unsafe refs and explicit text targets',
    () async {
      final backend = FakeBackend()
        ..elements = [
          ...elements(),
          ElementInfo(type: 'Text', text: 'Other', textMatchable: true),
        ];
      final manager = SessionManager(() => backend, coreCommands());
      addTearDown(manager.dispose);
      await manager.handle(request('connect', {'uri': 'http://localhost:1'}));
      final snapshot = await manager.handle(request('snapshot'));
      expect((snapshot.data!['elements'] as List)[1], isNot(contains('ref')));
      expect(
        (await manager.handle(request('tap', {'text': 'Save'}))).error?.code,
        'AMBIGUOUS_TARGET',
      );
      expect(backend.calls, isNot(contains('tap')));
    },
  );
  test(
    'new unknown text collision rejects a previously valid text ref',
    () async {
      final backend = FakeBackend()..elements = elements(collision: false);
      final manager = SessionManager(() => backend, coreCommands());
      addTearDown(manager.dispose);
      await manager.handle(request('connect', {'uri': 'http://localhost:1'}));
      final snapshot = await manager.handle(request('snapshot'));
      final ref = (snapshot.data!['elements'] as List).single['ref'];
      backend.elements = elements();
      expect(
        (await manager.handle(request('tap', {'ref': ref}))).error?.code,
        'AMBIGUOUS_TARGET',
      );
      expect(backend.calls, isNot(contains('tap')));
    },
  );
  test(
    'workflow waits reject unknown collisions and isolated display text',
    () async {
      final backend = FakeBackend()..elements = elements();
      final manager = SessionManager(() => backend, coreCommands());
      addTearDown(manager.dispose);
      await manager.handle(request('connect', {'uri': 'http://localhost:1'}));
      Future<Result> wait(String state) => manager.handle(
        request('workflow', {
          'workflow': {
            'schemaVersion': 1,
            'name': 'review',
            'steps': [
              {
                'id': 'wait',
                'action': 'wait',
                'target': {'text': 'Save'},
                'state': state,
              },
            ],
          },
          'inputs': <String, Object?>{},
        }),
      );
      expect((await wait('exists')).error?.code, 'AMBIGUOUS_TARGET');
      backend.elements = [elements().first];
      for (final state in ['exists', 'gone']) {
        expect((await wait(state)).error?.code, 'UNRESOLVABLE_TARGET');
      }
    },
  );
  test('ordinary text errors expose every outcome', () {
    for (final outcome in Outcome.values) {
      final error = AgentError(
        'BACKEND_ERROR',
        'Backend request failed',
        outcome: outcome,
      );
      expect(
        render(Result.failure('review', error), json: false),
        contains('Outcome: ${error.toJson()['outcome']}'),
      );
    }
  });
  test('oversized action response never reports not_sent', () async {
    final logging = configureDiagnosticLogging((_) {});
    final dir = await Directory('/tmp').createTemp('mra-delivery-');
    final runtime = await RuntimeDirectory.prepare(directory: dir.path);
    final backend = FakeBackend();
    backend.hooks['tap'] = () async {
      Logger('backend').info('x' * maxFrameBytes);
    };
    final server = DaemonServer(
      runtime,
      SessionManager(() => backend, coreCommands()),
    );
    final running = server.run();
    try {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!File(runtime.metadata).existsSync()) {
        if (DateTime.now().isAfter(end)) fail('Daemon did not start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final client = DaemonClient(runtime);
      expect(
        (await client.send(request('connect', {'uri': 'http://localhost:1'})))
            .exitCode,
        0,
      );
      final result = await client.send(request('tap', {'x': 1, 'y': 1}));
      expect(backend.calls.where((e) => e == 'tap'), hasLength(1));
      expect(result.error?.code, 'IO_ERROR');
      expect(result.error?.outcome, Outcome.unknown);
      await client.send(request('close'));
    } finally {
      await server.close();
      await running;
      await logging.cancel();
      await dir.delete(recursive: true);
    }
  });
}
