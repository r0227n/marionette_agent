import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

import 'arguments.dart';

/// Shared grammar and primitive for swipe and region scroll.
CliCommand swipeCommand({bool coordinates = true}) {
  final parser = ArgParser()
    ..addOption('distance', help: 'Positive logical pixels (default 200)');
  addSelectorOptions(parser);
  if (coordinates) {
    for (final name in _coordinates) {
      parser.addOption(name, help: 'Non-negative logical pixels');
    }
  }
  return CliCommand(parser, (args) {
    final params = <String, dynamic>{
      for (final name in [
        ...SelectorKind.values.map((k) => k.name),
        'distance',
        if (coordinates) ..._coordinates,
      ])
        if (args.wasParsed(name)) name: args.option(name),
    };
    final coordinateMode = _coordinates.any(params.containsKey);
    if (coordinateMode) {
      if (args.rest.isNotEmpty) {
        invalid('Coordinate swipe does not accept a target or direction');
      }
    } else {
      if (args.rest.isEmpty || args.rest.length > 2) {
        invalid(
          'Usage: ${coordinates ? 'swipe' : 'scroll'} <ref|selector> <left|right|up|down> [--distance <n>]',
        );
      }
      params['direction'] = args.rest.last;
      if (args.rest.length == 2) params['ref'] = args.rest.first;
    }
    _SwipeRequest.parse(params, coordinates: coordinates);
    return params;
  });
}

const _coordinates = ['start-x', 'start-y', 'end-x', 'end-y'];

/// Validate the entire IPC request before entering the mutation boundary.
Future<Json> handleSwipe(
  CommandContext context,
  Json params, {
  bool coordinates = true,
}) {
  final request = _SwipeRequest.parse(params, coordinates: coordinates);
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

class _SwipeRequest {
  _SwipeRequest({
    this.query,
    this.direction,
    this.distance = 200,
    this.gesture,
  });
  final TargetQuery? query;
  final Direction? direction;
  final double distance;
  final CoordinateSwipe? gesture;

  static _SwipeRequest parse(Json params, {required bool coordinates}) {
    final allowed = {
      'ref',
      'direction',
      'distance',
      ...SelectorKind.values.map((kind) => kind.name),
      if (coordinates) ..._coordinates,
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown gesture parameter');
    }
    if (_coordinates.any(params.containsKey)) {
      if (!coordinates ||
          params.keys.any((key) => !_coordinates.contains(key)) ||
          !_coordinates.every(params.containsKey)) {
        invalid(
          'Specify all four coordinates without a target, direction or distance',
        );
      }
      return _SwipeRequest(
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
    return _SwipeRequest(
      query: decodeTarget(params),
      direction: direction,
      distance: distance,
    );
  }
}
