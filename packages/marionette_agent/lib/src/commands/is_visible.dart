import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';
import 'command_context.dart';

TargetQuery stateTarget(Json params) {
  final allowed = {'action', 'ref', ...SelectorKind.values.map((k) => k.name)};
  if (!['visible', 'enabled', 'checked'].contains(params['action']) ||
      params.keys.any((key) => !allowed.contains(key))) {
    invalid('Usage: is visible|enabled|checked <ref|selector>');
  }
  return decodeTarget(params);
}

Future<Json> handleIs(CommandContext context, Json params) async {
  final element = await context.observeTarget(stateTarget(params));
  final value = switch (params['action']) {
    'enabled' => element.enabled,
    'checked' => element.checked,
    _ => element.visible,
  };
  return {
    if (params['action'] != 'visible') 'property': params['action'],
    'known': value != null,
    'value': value,
  };
}
