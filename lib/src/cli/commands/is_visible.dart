import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/is_visible.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

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
    stateTarget(params);
    return params;
  });
}
