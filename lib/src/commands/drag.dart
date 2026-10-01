import '../backend/backend.dart';
import '../protocol/protocol.dart';
import 'arguments.dart';
import 'command_context.dart';

Future<Json> handleDrag(CommandContext context, Json params) async {
  if (params.length != 2 || params['from'] is! Map || params['to'] is! Map) {
    invalid('Invalid drag arguments');
  }
  final from = asJson(params['from']), to = asJson(params['to']);
  final allowed = {'ref', ...SelectorKind.values.map((kind) => kind.name)};
  if ([...from.keys, ...to.keys].any((key) => !allowed.contains(key))) {
    invalid('Invalid drag targets');
  }
  final source = decodeTarget(from), destination = decodeTarget(to);
  await context.requireInteraction('drag');
  return context.performTargets(
    [source, destination],
    (backend, selectors) => (backend as InteractionBackend).interact(
      'drag',
      target: selectors[0],
      arguments: {'destination': selectors[1].toJson()},
    ),
  );
}
