import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand batchCommand() => CliCommand(ArgParser(), (args) {
  if (args.rest.length != 1 || args.rest.single.isEmpty) {
    invalid('Usage: batch <JSON-file|->');
  }
  return {'path': args.rest.single};
});
