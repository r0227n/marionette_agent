import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

import 'arguments.dart';

CliCommand isCommand() {
  final parser = ArgParser();
  for (final name in ['visible', 'enabled', 'checked']) {
    final child = ArgParser();
    addSelectorOptions(child);
    parser.addCommand(name, child);
  }
  return CliCommand(parser, (args) {
    final action = args.command;
    if (action == null || action.rest.length > 1) {
      invalid('Usage: is visible|enabled|checked <ref|selector>');
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
  if (!['visible', 'enabled', 'checked'].contains(params['action']) ||
      params.keys.any((key) => !allowed.contains(key))) {
    invalid('Usage: is visible|enabled|checked <ref|selector>');
  }
  return decodeTarget(params);
}

Future<Json> handleIs(CommandContext context, Json params) async {
  final element = await context.observeTarget(_target(params));
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
