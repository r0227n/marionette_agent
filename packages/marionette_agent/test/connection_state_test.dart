import 'dart:io';

import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/cli/state_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 10));
  Matcher code(String value) =>
      isA<AgentError>().having((error) => error.code, 'code', value);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mra-state-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'state roundtrip keeps credentials private and refuses overwrite',
    () async {
      final file = File('${directory.path}/connection.json');
      final result = await saveConnectionState(file.path, {
        'uri': 'http://127.0.0.1:1234/private-token/',
      }, deadline());
      expect(result.toString(), isNot(contains('private-token')));
      expect(
        await loadConnectionState(file.path, deadline()),
        'ws://127.0.0.1:1234/private-token/ws',
      );
      final saved = await file.readAsBytes();
      await expectLater(
        saveConnectionState(file.path, {
          'uri': 'http://localhost:1/',
        }, deadline()),
        throwsA(code('IO_ERROR')),
      );
      expect(await file.readAsBytes(), saved);
      await Process.run('/bin/chmod', ['644', file.path]);
      await expectLater(
        loadConnectionState(file.path, deadline()),
        throwsA(code('IO_ERROR')),
      );
      await Process.run('/bin/chmod', ['600', file.path]);
      final link = Link('${directory.path}/linked.json');
      await link.create(file.path);
      await expectLater(
        loadConnectionState(link.path, deadline()),
        throwsA(code('IO_ERROR')),
      );
    },
  );

  test(
    'expired state operations report TIMEOUT and leave no partial file',
    () async {
      final file = File('${directory.path}/connection.json');
      final expired = DateTime.now().subtract(const Duration(seconds: 1));
      await expectLater(
        saveConnectionState(file.path, {'uri': 'http://localhost:1/'}, expired),
        throwsA(code('TIMEOUT')),
      );
      expect(await file.exists(), isFalse);
      await expectLater(
        loadConnectionState(file.path, expired),
        throwsA(code('TIMEOUT')),
      );
    },
  );
}
