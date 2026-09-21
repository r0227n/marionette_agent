import 'package:args/args.dart';

import '../../commands/arguments.dart';
import '../../protocol/protocol.dart';
import '../command.dart';

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
