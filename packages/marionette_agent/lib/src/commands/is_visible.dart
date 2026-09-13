import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

import 'arguments.dart';

CliCommand isCommand() {
  final visible = ArgParser();
  addSelectorOptions(visible);
  return CliCommand(ArgParser()..addCommand('visible', visible), (args) {
    final action = args.command;
    if (action == null || action.rest.length > 1) {
      invalid('Usage: is visible <ref|selector>');
    }
    final params = <String, dynamic>{
      'action': action.name,
      if (action.rest.isNotEmpty) 'ref': action.rest.single,
      for (final kind in SelectorKind.values)
        if (action.wasParsed(kind.name)) kind.name: action.option(kind.name),
    };
    _target(params);
    return params;
  });
}

TargetQuery _target(Json params) {
  final allowed = {'action', 'ref', ...SelectorKind.values.map((k) => k.name)};
  if (params['action'] != 'visible' ||
      params.keys.any((key) => !allowed.contains(key))) {
    invalid('Usage: is visible <ref|selector>');
  }
  return decodeTarget(params);
}

Future<Json> handleIs(CommandContext context, Json params) async {
  final element = await context.observeTarget(_target(params));
  return {'known': element.visible != null, 'value': element.visible};
}
