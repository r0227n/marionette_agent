import 'dart:io';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';

void main() {
  test('removed Flutter recording is rejected by CLI', () {
    expect(
      () => CliParser().parse([
        'record',
        'start',
        'capture.mp4',
        '--platform',
        'flutter',
        '--device',
        'session',
      ]),
      throwsA(isA<AgentError>()),
    );
  });

  test('Flutter recording requires a connected backend with an isolated capture capability', () async {
    final manager = SessionManager(FakeBackend.new, coreCommands());
    addTearDown(manager.dispose);
    final dir = await Directory.systemTemp.createTemp('flutter-record-test-');
    addTearDown(() => dir.delete(recursive: true));
    Future<Result> call(String command, Json params) => manager.handle(
      Request(
        requestId: 'test',
        session: 'a',
        command: command,
        params: params,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    final params = {
      'action': 'start',
      'platform': 'flutter',
      'device': 'session',
      'path': '${dir.path}/capture.mp4',
    };
    expect((await call('record', params)).error!.code, 'INVALID_ARGUMENT');
    // The first empty session may retire its manager, as for other failed starts.
    final connected = SessionManager(FakeBackend.new, coreCommands());
    addTearDown(connected.dispose);
    await connected.handle(
      Request(
        requestId: 'connect',
        session: 'a',
        command: 'connect',
        params: {'uri': 'http://localhost:1/'},
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    final result = await connected.handle(
      Request(
        requestId: 'record',
        session: 'a',
        command: 'record',
        params: params,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    expect(result.error!.code, 'INVALID_ARGUMENT');
    expect(File('${dir.path}/capture.mp4').existsSync(), false);
  });
}
