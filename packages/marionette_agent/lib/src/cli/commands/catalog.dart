import 'package:args/args.dart';

import '../../commands/interactions.dart'
    show targetInteractions, keyboardInteractions;
import '../../protocol/protocol.dart';
import '../command.dart';
import 'actions.dart';
import 'batch.dart';
import 'diff.dart';
import 'drag.dart';
import 'find.dart';
import 'get.dart';
import 'install.dart';
import 'interactions.dart';
import 'is_visible.dart';
import 'keyboard.dart';
import 'observations.dart';
import 'record.dart';
import 'state.dart';
import 'swipe.dart';
import 'wait.dart';
import 'workflow.dart';

Map<String, CliCommand> builtInCommands() => {
  'device': CliCommand(
    ArgParser()..addCommand(
      'list',
      ArgParser()
        ..addOption('platform', allowed: ['ios', 'android'], defaultsTo: 'ios'),
    ),
    (args) {
      final child = args.command;
      if (child == null || args.rest.isNotEmpty || child.rest.isNotEmpty) {
        invalid('Usage: device list [--platform ios|android]');
      }
      return {'platform': child.option('platform')};
    },
  ),
  'doctor': CliCommand(
    ArgParser()
      ..addOption('probe-uri')
      ..addFlag('quick', negatable: false)
      ..addFlag('offline', negatable: false)
      ..addFlag('fix', negatable: false),
    (args) {
      if (args.rest.isNotEmpty) invalid('Usage: doctor [--probe-uri <uri>]');
      return {
        'probeUri': args['probe-uri'],
        if (args.flag('quick')) 'quick': true,
        if (args.flag('offline')) 'offline': true,
        if (args.flag('fix')) 'fix': true,
      };
    },
  ),
  'workflow': workflowCommand(),
  'record': recordCommand(),
  'tap': actionCommand(),
  'click': actionCommand(),
  for (final action in [...targetInteractions, ...keyboardInteractions])
    action: interactionCommand(action),
  'fill': actionCommand(fill: true),
  'scroll': swipeCommand(coordinates: false),
  'screenshot': screenshotCommand(),
  'logs': CliCommand(ArgParser(), noArguments),
  'wait': waitCommand(),
  'get': getCommand(),
  'find': findCommand(),
  'diff': diffCommand(),
  'batch': batchCommand(),
  'state': stateCommand(),
  'install': installCommand(),
  'upgrade': installCommand(),
  for (final command in ['confirm', 'deny'])
    command: CliCommand(ArgParser(), (args) {
      if (args.rest.length != 1 ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(args.rest.single)) {
        invalid('Specify one confirmation id');
      }
      return {'id': args.rest.single};
    }),
  'keyboard': keyboardCommand(),
  'drag': dragCommand(),
  'clipboard': clipboardCommand(),
  'is': isCommand(),
  'swipe': swipeCommand(),
  'connect': CliCommand(ArgParser(), (args) {
    if (args.rest.length != 1) invalid('Usage: connect <uri>');
    return {'uri': args.rest.single};
  }),
  'snapshot': snapshotCommand(),
  'close': CliCommand(
    ArgParser()..addFlag(
      'all',
      negatable: false,
      help: 'Close every session and stop the daemon.',
    ),
    (args) {
      noArguments(args);
      return args['all'] == true ? {'all': true} : {};
    },
  ),
  'session': CliCommand(
    ArgParser()
      ..addCommand('list')
      ..addCommand('show'),
    (args) {
      final action = args.command;
      if (action == null || action.rest.isNotEmpty) {
        invalid('Usage: session list|show');
      }
      return {'action': action.name};
    },
  ),
};
