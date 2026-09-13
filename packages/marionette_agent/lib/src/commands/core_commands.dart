import '../protocol/protocol.dart';
import 'registry.dart';
import 'swipe.dart';
import 'actions.dart';
import 'get.dart';
import 'observations.dart';
import 'wait.dart';
import 'is_visible.dart';
import 'interactions.dart';
import 'find.dart';
import 'keyboard.dart';
import 'drag.dart';

/// Registers the initial product command set.
CommandRegistry coreCommands() {
  final registry = CommandRegistry()
    ..register('swipe', handleSwipe)
    ..register('tap', handleTap)
    ..register('click', handleTap)
    ..register('fill', handleFill)
    ..register(
      'scroll',
      (context, params) async => {
        ...await handleSwipe(context, params, coordinates: false),
        'command': 'scroll',
      },
    )
    ..register('screenshot', handleScreenshot)
    ..register('logs', handleLogs)
    ..register('wait', handleWait)
    ..register('get', handleGet)
    ..register('find', handleFind)
    ..register('keyboard', handleKeyboard)
    ..register('drag', handleDrag)
    ..register('clipboard', handleClipboard)
    ..register('is', handleIs)
    ..register('snapshot', handleSnapshot)
    ..register('diff-snapshot', (context, params) {
      if (params.isNotEmpty) invalid('Invalid snapshot comparison request');
      return context.read(
        (backend) async => {
          'elements': [
            for (final element in await backend.inspect()) element.toJson(),
          ],
        },
      );
    });

  for (final action in [...targetInteractions, ...keyboardInteractions]) {
    registry.register(
      action,
      (context, params) => handleInteraction(context, action, params),
    );
  }
  return registry;
}
