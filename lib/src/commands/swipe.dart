import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';
import 'command_context.dart';

const swipeCoordinates = ['start-x', 'start-y', 'end-x', 'end-y'];

/// Validate the entire IPC request before entering the mutation boundary.
Future<Json> handleSwipe(
  CommandContext context,
  Json params, {
  bool coordinates = true,
}) {
  final request = SwipeRequest.parse(params, coordinates: coordinates);
  final gesture = request.gesture;
  if (gesture != null) {
    return context.performCoordinates((backend) => backend.swipe(gesture));
  }
  return context.performTarget(
    request.query!,
    (backend, selector) => backend.swipe(
      ElementSwipe(selector, request.direction!, distance: request.distance),
    ),
  );
}

class SwipeRequest {
  SwipeRequest({this.query, this.direction, this.distance = 200, this.gesture});
  final TargetQuery? query;
  final Direction? direction;
  final double distance;
  final CoordinateSwipe? gesture;

  static SwipeRequest parse(Json params, {required bool coordinates}) {
    final allowed = {
      'ref',
      'direction',
      'distance',
      ...SelectorKind.values.map((kind) => kind.name),
      if (coordinates) ...swipeCoordinates,
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown gesture parameter');
    }
    if (swipeCoordinates.any(params.containsKey)) {
      if (!coordinates ||
          params.keys.any((key) => !swipeCoordinates.contains(key)) ||
          !swipeCoordinates.every(params.containsKey)) {
        invalid(
          'Specify all four coordinates without a target, direction or distance',
        );
      }
      return SwipeRequest(
        gesture: CoordinateSwipe(
          Point(
            finiteNumber(params['start-x']),
            finiteNumber(params['start-y']),
          ),
          Point(finiteNumber(params['end-x']), finiteNumber(params['end-y'])),
        ),
      );
    }
    final direction = Direction.values
        .where((value) => value.name == params['direction'])
        .firstOrNull;
    if (direction == null) invalid('Direction must be left, right, up or down');
    final distance = params.containsKey('distance')
        ? finiteNumber(params['distance'])
        : 200.0;
    if (distance <= 0) invalid('Distance must be positive');
    return SwipeRequest(
      query: decodeTarget(params),
      direction: direction,
      distance: distance,
    );
  }
}
