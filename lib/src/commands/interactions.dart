import '../backend/backend.dart';
import '../protocol/protocol.dart';
import 'command_context.dart';
import 'interaction_request.dart';

export 'interaction_request.dart';

Future<Json> handleInteraction(
  CommandContext context,
  String action,
  Json params,
) async {
  final request = InteractionRequest.parse(action, params);
  return executeInteraction(context, request);
}

Future<Json> executeInteraction(
  CommandContext context,
  InteractionRequest request,
) async {
  final action = request.action;
  await context.requireInteraction(action);
  if (request.target == null) {
    return context.performCoordinates(
      (backend) => (backend as InteractionBackend).interact(
        action,
        arguments: request.arguments,
      ),
    );
  }
  if (action == 'scrollintoview') {
    // Visibility is allowed to be false, but target uniqueness is still required.
    final resolved = await context.resolveRead(request.target!);
    return context.performCoordinates(
      (backend) => (backend as InteractionBackend).interact(
        action,
        target: resolved.selector,
        arguments: request.arguments,
      ),
    );
  }
  return context.performTarget(
    request.target!,
    (backend, selector) => (backend as InteractionBackend).interact(
      action,
      target: selector,
      arguments: request.arguments,
    ),
  );
}
