import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/actions.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

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
    ActionRequest.parse(params, fill: fill);
    return params;
  });
}
