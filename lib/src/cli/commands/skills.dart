import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../command.dart';
import '../help.dart';

CliCommand skillsCommand() => CliCommand(
  ArgParser()
    ..addCommand('list')
    ..addCommand(
      'get',
      ArgParser()
        ..addFlag('full', negatable: false)
        ..addFlag('all', negatable: false),
    )
    ..addCommand('path'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty) invalid(skillsUsage);
    switch (child?.name) {
      case null:
      case 'list':
        if (child != null) noArguments(child);
        return {'action': 'list'};
      case 'get':
        if (child!.rest.isEmpty && !child.flag('all')) {
          invalid(
            'No skill name provided. Usage: marionette-agent skills get <name>',
          );
        }
        return {
          'action': 'get',
          'names': child.rest,
          'all': child.flag('all'),
          'full': child.flag('full'),
        };
      case 'path':
        if (child!.rest.length > 1) {
          invalid('Usage: marionette-agent skills path [name]');
        }
        return {'action': 'path', 'name': child.rest.firstOrNull};
      default:
        invalid(skillsUsage);
    }
  },
);
