import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

import 'arguments.dart';

/// Targeted tap/fill grammar; fill input remains an opaque string.
CliCommand actionCommand({bool fill = false}) {
  final parser = ArgParser();
  addSelectorOptions(parser);
  if (!fill) {
    parser.addOption('x');
    parser.addOption('y');
  }
  return CliCommand(parser, (args) {
    final params = <String, dynamic>{
      for (final name in [
        ...SelectorKind.values.map((k) => k.name),
        if (!fill) ...['x', 'y'],
      ])
        if (args.wasParsed(name)) name: args.option(name),
    };
    final rest = args.rest.toList();
    if (fill) {
      if (rest.isEmpty) invalid('Usage: fill <ref|selector> <text>');
      params['input'] = rest.removeLast();
    }
    if (rest.length > 1) invalid('Specify one target');
    if (rest.isNotEmpty) params['ref'] = rest.single;
    _Action.parse(params, fill: fill);
    return params;
  });
}

Future<Json> handleTap(CommandContext context, Json params) {
  final action = _Action.parse(params, fill: false);
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
  final action = _Action.parse(params, fill: true);
  return context.performTarget(
    action.query!,
    (backend, selector) => backend.fill(selector, action.input!),
  );
}

class _Action {
  _Action({this.query, this.point, this.input});
  final TargetQuery? query;
  final Point? point;
  final String? input;

  static _Action parse(Json params, {required bool fill}) {
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
      return _Action(
        point: Point(finiteNumber(params['x']), finiteNumber(params['y'])),
      );
    }
    return _Action(query: decodeTarget(params), input: input as String?);
  }
}
