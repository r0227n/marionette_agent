import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand stateCommand() => CliCommand(
  ArgParser()
    ..addCommand('save')
    ..addCommand('load'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty ||
        child == null ||
        child.rest.length != 1 ||
        child.rest.single.isEmpty) {
      invalid('Usage: state save|load <path>');
    }
    return {'action': child.name, 'path': child.rest.single};
  },
);
