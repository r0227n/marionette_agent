import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../command.dart';
import '../workflow_loader.dart';

CliCommand workflowCommand() {
  final parser = ArgParser()..addCommand('schema');
  for (final action in ['validate', 'run']) {
    final child = ArgParser()
      ..addOption('format', allowed: ['json', 'yaml'])
      ..addOption('inputs')
      ..addOption('inputs-format', allowed: ['json', 'yaml']);
    if (action == 'validate') child.addFlag('check-inputs', negatable: false);
    parser.addCommand(action, child);
  }
  return CliCommand(parser, (args) {
    final sub = args.command;
    if (args.rest.isNotEmpty || sub == null) {
      invalid('Usage: workflow schema|validate|run');
    }
    if (sub.name == 'schema') {
      if (sub.rest.length > 1) invalid('Usage: workflow schema [action]');
      return {'action': 'schema', 'schemaAction': sub.rest.firstOrNull};
    }
    if (sub.rest.length != 1) invalid('Workflow requires exactly one path');
    final file = sub.rest.single;
    final inputs = sub.option('inputs');
    if (file == '-' && inputs == '-') invalid('Only one input may use stdin');
    if (inputs == null && sub.wasParsed('inputs-format')) {
      invalid('inputs-format requires inputs');
    }
    return {
      'action': sub.name,
      'path': file,
      'format': workflowFormat(file, sub.option('format')),
      'inputsPath': ?inputs,
      if (inputs != null)
        'inputsFormat': workflowFormat(inputs, sub.option('inputs-format')),
      'bind': sub.name == 'run' || inputs != null || sub.flag('check-inputs'),
    };
  });
}
