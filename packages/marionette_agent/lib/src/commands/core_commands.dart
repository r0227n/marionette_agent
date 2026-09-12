import '../protocol/protocol.dart';
import 'registry.dart';
import 'swipe.dart';
import 'actions.dart';
import 'observations.dart';
import 'wait.dart';

/// Registers the initial product command set.
CommandRegistry coreCommands() => CommandRegistry()
  ..register('swipe', handleSwipe)
  ..register('tap', handleTap)
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
  ..register('snapshot', (context, params) {
    if (params.isNotEmpty) invalid('Usage: snapshot');
    return context.snapshot();
  });
