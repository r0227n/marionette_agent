import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/mcp/catalog.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/workflow/model.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/fake_screen_capturer.dart';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import 'support/requests.dart';

void main() {
  test('macOS CLI and MCP select a display instead of a device', () {
    final parser = CliParser(environment: {});
    final tool = mcpToolCatalog().singleWhere((t) => t.name == 'screenshot');
    expect(
      parser
          .parse(
            tool.arguments({
              'source': 'macos',
              'display': 2,
            }, const CommonOptions()),
          )
          .params,
      {'source': 'macos', 'display': 2},
    );
    for (final args in [
      ['--source=macos'],
      ['--display=1'],
      ['--source=macos', '--display=01'],
      ['--source=macos', '--display=1000'],
      ['--source=macos', '--display=1', '--device=x'],
      ['--source=flutter'],
      ['--source=macos', '--display=1', '--annotate'],
    ]) {
      expect(
        () => parser.parse(['screenshot', ...args]),
        throwsA(isA<AgentError>()),
        reason: '$args',
      );
    }
  });
  test(
    'macOS standalone and workflow run without Flutter; errors never fall back',
    () async {
      final backend = FakeBackend();
      final capturer = FakeScreenCapturer(
        image.encodePng(image.Image(width: 4, height: 2)),
      );
      SessionManager makeManager() => SessionManager(
        () => backend,
        coreCommands(),
        screenCapturer: capturer,
      );
      final manager = makeManager();
      addTearDown(manager.dispose);
      final native = {'source': 'macos', 'display': 2};
      final shot = await manager.handle(request('screenshot', params: native));
      expect(shot.error, isNull);
      expect(shot.data!['capture'], containsPair('device', '2'));
      final workflow = {
        'schemaVersion': 1,
        'name': 'macos',
        'steps': [
          {'id': 'proof', 'action': 'screenshot', ...native},
        ],
      };
      expect(WorkflowPlan.decode(workflow).nativeOnly, isTrue);
      final workflowManager = makeManager();
      addTearDown(workflowManager.dispose);
      final result = await workflowManager.handle(
        request(
          'workflow',
          params: {'workflow': workflow, 'inputs': <String, Object?>{}},
        ),
      );
      expect(result.error, isNull);
      expect(result.data!['completedSteps'], 1);
      expect((result.data!['screenshots'] as List).single['stepId'], 'proof');
      capturer.failure = const PlatformException(
        'SCREEN_CAPTURE_PERMISSION_REQUIRED',
        'Permission missing',
      );
      final deniedManager = makeManager();
      addTearDown(deniedManager.dispose);
      final denied = await deniedManager.handle(
        request('screenshot', params: native),
      );
      expect(denied.error!.code, 'SCREEN_CAPTURE_PERMISSION_REQUIRED');
      expect(capturer.devices, ['2', '2', '2']);
      expect(capturer.sources, ['macos', 'macos', 'macos']);
      expect(backend.calls, isEmpty);
    },
  );
}
