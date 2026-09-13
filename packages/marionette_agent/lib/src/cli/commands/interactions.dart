import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/interactions.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

CliCommand interactionCommand(String action) {
  final parser = ArgParser();
  final keyboard = keyboardInteractions.contains(action);
  if (!keyboard) addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    final rest = args.rest.toList();
    final params = <String, Object?>{};
    if (keyboard) {
      if (rest.length != 1) invalid('Specify one key or key combination');
      params['input'] = rest.removeLast();
    } else {
      for (final kind in SelectorKind.values) {
        if (args.wasParsed(kind.name)) {
          params[kind.name] = args.option(kind.name);
        }
      }
      if (action == 'type' || action == 'select') {
        if (rest.isEmpty) invalid('A text or option value is required');
        params['input'] = rest.removeLast();
      }
      if (rest.length > 1) invalid('Specify one ref or selector');
      if (rest.isNotEmpty) params['ref'] = rest.single;
    }
    InteractionRequest.parse(action, params);
    return params;
  });
}
