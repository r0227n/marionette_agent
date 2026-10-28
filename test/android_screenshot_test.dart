import 'dart:io';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/mcp/catalog.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/fake_screen_capturer.dart';
import 'support/requests.dart';

void main() {
  test('Android capture is explicit and resolves its pairing before IPC', () {
    final parser = CliParser(environment: {});
    for (final args in [
      ['screenshot'],
      ['diff', 'screenshot', '--baseline', 'before.png'],
    ]) {
      final invocation = parser.parse([
        ...args,
        '--source',
        'android-emulator',
        '--device',
        'capture-pairing.json',
      ]);
      expect(
        invocation.params['device'],
        File('capture-pairing.json').absolute.path,
      );
      expect(invocation.params['source'], 'android-emulator');
    }
    expect(parser.parse(['screenshot', '--device', screenshotDevice]).params, {
      'device': screenshotDevice,
    });
    expect(
      () => parser.parse(['native', 'snapshot']),
      throwsA(isA<AgentError>()),
    );
    expect(
      mcpToolCatalog().any((tool) => tool.name == 'native_screenshot'),
      isFalse,
    );
  });

  test(
    'standalone and workflow preserve the explicit acquisition source',
    () async {
      final backend = FakeBackend();
      final capturer = FakeScreenCapturer([1, 2, 3]);
      final manager = SessionManager(
        () => backend,
        coreCommands(),
        screenCapturer: capturer,
      );
      addTearDown(manager.dispose);
      final params = <String, Object?>{
        'source': 'android-emulator',
        'device': 'private-pairing.json',
      };
      final single = await manager.handle(
        request('screenshot', params: params),
      );
      expect(single.error, isNull);
      expect(single.data!['capture'], containsPair('method', 'uiautomator'));
      final workflowManager = SessionManager(
        () => backend,
        coreCommands(),
        screenCapturer: capturer,
      );
      addTearDown(workflowManager.dispose);
      final workflow = await workflowManager.handle(
        request(
          'workflow',
          params: {
            'workflow': {
              'schemaVersion': 1,
              'name': 'android',
              'steps': [
                {'id': 'screen', 'action': 'screenshot', ...params},
              ],
            },
            'inputs': <String, Object?>{},
          },
        ),
      );
      expect(workflow.error, isNull);
      expect(capturer.sources, ['android-emulator', 'android-emulator']);
      expect(backend.calls, isEmpty);
    },
  );
}
