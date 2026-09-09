import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

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
      return _Action(point: Point(_number(params['x']), _number(params['y'])));
    }
    final selectors = SelectorKind.values
        .where((k) => params.containsKey(k.name))
        .toList();
    if ((params.containsKey('ref') ? 1 : 0) + selectors.length != 1) {
      invalid('Specify exactly one ref or selector');
    }
    final TargetQuery query;
    if (params.containsKey('ref')) {
      final ref = params['ref'];
      if (ref is! String) invalid('Expected a ref');
      query = RefQuery(ref);
    } else {
      final kind = selectors.single;
      final value = params[kind.name];
      if (value is! String || value.isEmpty) {
        invalid('Selector value must not be empty');
      }
      query = SelectorQuery(Selector(kind, value));
    }
    return _Action(query: query, input: input as String?);
  }
}

double _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  if (number == null || !number.isFinite) {
    invalid('Expected a finite coordinate');
  }
  return number;
}
