import '../protocol/protocol.dart';
import 'registry.dart';
import 'swipe.dart';
import 'actions.dart';
import 'get.dart';
import 'observations.dart';
import 'wait.dart';
import 'is_visible.dart';

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
  ..register('get', handleGet)
  ..register('is', handleIs)
  ..register('snapshot', (context, params) {
    if (params.isNotEmpty) invalid('Usage: snapshot');
    return context.snapshot();
  });
