import 'package:args/args.dart';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import 'parser.dart';
import 'target_options.dart';

CliCommand getCommand() {
  final parser = ArgParser();
  for (final action in ['text', 'box', 'count']) {
    final command = ArgParser();
    addSelectorOptions(command);
    parser.addCommand(action, command);
  }
  return CliCommand(parser, (args) {
    final action = args.command;
    if (action == null) {
      invalid('Usage: get text|box <ref|selector> | get count <selector>');
    }
    final ref = action.rest.isEmpty ? null : action.rest.singleOrNull;
    if (action.rest.length > 1) {
      invalid('Usage: get ${action.name} <ref|selector>');
    }
    if (action.name == 'count' && ref != null) {
      invalid('get count requires a selector');
    }
    parseTarget(action, ref: ref);
    return {
      'action': action.name,
      'ref': ?ref,
      for (final kind in SelectorKind.values)
        if (action.wasParsed(kind.name)) kind.name: action.option(kind.name),
    };
  });
}
