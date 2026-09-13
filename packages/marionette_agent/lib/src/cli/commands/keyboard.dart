import 'package:args/args.dart';

import '../../commands/interactions.dart';
import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand keyboardCommand() => CliCommand(
  ArgParser()
    ..addCommand('press')
    ..addCommand('type')
    ..addCommand('inserttext'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty || child == null || child.rest.length != 1) {
      invalid('Usage: keyboard press|type|inserttext <input>');
    }
    if (child.name == 'press') parseKey(child.rest.single);
    return {'action': child.name, 'input': child.rest.single};
  },
);

CliCommand clipboardCommand() => CliCommand(
  ArgParser()
    ..addCommand('read')
    ..addCommand('write')
    ..addCommand('copy')
    ..addCommand('paste'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty ||
        child == null ||
        child.rest.length != (child.name == 'write' ? 1 : 0)) {
      invalid('Usage: clipboard read|write <text>|copy|paste');
    }
    return {
      'action': child.name,
      if (child.name == 'write') 'input': child.rest.single,
    };
  },
);
