import 'package:args/args.dart';

import '../backend/backend.dart';
import '../cli/parser.dart';
import '../protocol/protocol.dart';
import 'arguments.dart';
import 'command_context.dart';

CliCommand dragCommand() => CliCommand(
  ArgParser()
    ..addOption('from-key')
    ..addOption('to-key'),
  (args) {
    final Json params;
    if (args.rest.length == 2 &&
        !args.wasParsed('from-key') &&
        !args.wasParsed('to-key')) {
      params = {
        'from': {'ref': args.rest[0]},
        'to': {'ref': args.rest[1]},
      };
    } else if (args.rest.isEmpty &&
        args.wasParsed('from-key') &&
        args.wasParsed('to-key')) {
      params = {
        'from': {'key': args.option('from-key')},
        'to': {'key': args.option('to-key')},
      };
    } else {
      invalid(
        'Usage: drag <from-ref> <to-ref> | drag --from-key <key> --to-key <key>',
      );
    }
    decodeTarget(asJson(params['from']));
    decodeTarget(asJson(params['to']));
    return params;
  },
);

Future<Json> handleDrag(CommandContext context, Json params) async {
  if (params.length != 2 || params['from'] is! Map || params['to'] is! Map) {
    invalid('Invalid drag arguments');
  }
  final from = asJson(params['from']), to = asJson(params['to']);
  final allowed = {'ref', ...SelectorKind.values.map((kind) => kind.name)};
  if ([...from.keys, ...to.keys].any((key) => !allowed.contains(key))) {
    invalid('Invalid drag targets');
  }
  final source = decodeTarget(from), destination = decodeTarget(to);
  await context.requireInteraction('drag');
  final start = await context.resolveRead(source),
      end = await context.resolveRead(destination);
  if (start.element.visible == false || end.element.visible == false) {
    throw const AgentError(
      'UNRESOLVABLE_TARGET',
      'Drag targets must be visible',
    );
  }
  return context.performTarget(
    source,
    (backend, selector) => (backend as InteractionBackend).interact(
      'drag',
      target: selector,
      arguments: {'destination': end.selector.toJson()},
    ),
  );
}
