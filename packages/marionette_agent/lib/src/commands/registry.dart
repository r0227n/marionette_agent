import '../protocol/protocol.dart';
import 'command_context.dart';

/// A handler must validate before using context. Context guards every await.
/// CommandContext operation methods handle target resolution and ref invalidation.
typedef CommandHandler = Future<Json> Function(
  CommandContext context,
  Json params,
);

/// Resolve handler by name. SessionManager owns execution queueing and exception classification.
class CommandRegistry {
  final _handlers = <String, CommandHandler>{};
  void register(String name, CommandHandler handler) {
    if (_handlers.containsKey(name)) {
      throw ArgumentError('Duplicate command registration');
    }
    _handlers[name] = handler;
  }

  Future<Json> dispatch(CommandContext context, String command, Json params) {
    final handler = _handlers[command];
    if (handler == null) invalid('Unknown command');
    return handler(context, params);
  }
}
