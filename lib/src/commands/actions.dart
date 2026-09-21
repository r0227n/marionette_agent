import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';
import 'command_context.dart';

Future<Json> handleTap(CommandContext context, Json params) {
  final action = ActionRequest.parse(params, fill: false);
  return executeTap(context, action);
}

Future<Json> executeTap(CommandContext context, ActionRequest action) {
  if (action.point case final Point point) {
    return context.performCoordinates(
      (backend) => backend.tap(CoordinateTarget(point)),
    );
  }
  return context.performTarget(
    action.query!,
    (backend, selector) => backend.tap(ElementTarget(selector)),
  );
}

Future<Json> handleFill(CommandContext context, Json params) {
  final action = ActionRequest.parse(params, fill: true);
  return executeFill(context, action);
}

Future<Json> executeFill(CommandContext context, ActionRequest action) {
  return context.performTarget(
    action.query!,
    (backend, selector) => backend.fill(selector, action.input!),
  );
}

class ActionRequest {
  ActionRequest({this.query, this.point, this.input});
  final TargetQuery? query;
  final Point? point;
  final String? input;

  static ActionRequest parse(Json params, {required bool fill}) {
    final allowed = {
      'ref',
      ...SelectorKind.values.map((k) => k.name),
      if (fill) 'input' else ...['x', 'y'],
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown action parameter');
    }
    final input = params['input'];
    if (fill && input is! String) invalid('Fill requires a text argument');
    if (!fill && (params.containsKey('x') || params.containsKey('y'))) {
      if (params.length != 2 ||
          !params.containsKey('x') ||
          !params.containsKey('y')) {
        invalid('Specify both x and y without a target');
      }
      return ActionRequest(
        point: Point(finiteNumber(params['x']), finiteNumber(params['y'])),
      );
    }
    return ActionRequest(query: decodeTarget(params), input: input as String?);
  }
}
