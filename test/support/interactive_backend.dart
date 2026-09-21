import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';

import 'fake_backend.dart';

class InteractiveFake extends FakeBackend
    implements InteractionBackend, ClipboardBackend {
  @override
  Set<String> interactions = {
    'dblclick',
    'press',
    'type',
    'check',
    'uncheck',
    'focus',
    'hover',
    'select',
    'scrollintoview',
    'drag',
    'keydown',
    'keyup',
    'keyboard.inserttext',
    'clipboard.read',
    'clipboard.write',
    'clipboard.copy',
    'clipboard.paste',
  };
  Json? lastArguments;
  @override
  Future<void> interact(
    String action, {
    Selector? target,
    Json arguments = const {},
  }) async {
    calls.add(action);
    lastArguments = arguments;
    await hooks[action]?.call();
  }

  @override
  Future<String?> readClipboard() async => 'clipboard';
}
