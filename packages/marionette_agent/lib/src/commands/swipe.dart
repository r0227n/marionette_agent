import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

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
          Point(_number(params['start-x']), _number(params['start-y'])),
          Point(_number(params['end-x']), _number(params['end-y'])),
        ),
      );
    }
    final direction = Direction.values
        .where((value) => value.name == params['direction'])
        .firstOrNull;
    if (direction == null) invalid('Direction must be left, right, up or down');
    final distance = params.containsKey('distance')
        ? _number(params['distance'])
        : 200.0;
    if (distance <= 0) invalid('Distance must be positive');
    final selected = SelectorKind.values
        .where((kind) => params.containsKey(kind.name))
        .toList();
    if ((params.containsKey('ref') ? 1 : 0) + selected.length != 1) {
      invalid('Specify exactly one ref or selector');
    }
    final TargetQuery query;
    if (params.containsKey('ref')) {
      final ref = params['ref'];
      if (ref is! String) invalid('Expected a ref');
      query = RefQuery(ref);
    } else {
      final kind = selected.single;
      final value = params[kind.name];
      if (value is! String || value.isEmpty) {
        invalid('Selector value must not be empty');
      }
      query = SelectorQuery(Selector(kind, value));
    }
    return _SwipeRequest(
      query: query,
      direction: direction,
      distance: distance,
    );
  }
}

double _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  if (number == null || !number.isFinite) invalid('Expected a finite number');
  return number;
}
