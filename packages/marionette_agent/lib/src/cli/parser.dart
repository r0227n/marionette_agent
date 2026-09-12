import 'package:args/args.dart';

import 'common_options.dart';
import '../protocol/protocol.dart';
import '../commands/swipe.dart';
import '../commands/actions.dart';
import '../commands/observations.dart';
import 'workflow_command.dart';
import 'record_command.dart';
import 'wait_command.dart';

/// Register ArgParser grammar and conversion from validated args to protocol params.
class CliCommand {
  CliCommand(this.parser, this.decode);
  final ArgParser parser;
  final Json Function(ArgResults) decode;
}

/// args owns tokenization, subcommands, option values, -- and usage rendering.
/// Only the product's duplicate-option and value constraints are custom.
class CliParser {
  CliParser({Map<String, CliCommand> commands = const {}}) {
    definitions.addAll(commands);
    for (final entry in definitions.entries) {
      parser.addCommand(entry.key, entry.value.parser);
    }
  }
  final parser = CommonOptions.createParser();
  final definitions = <String, CliCommand>{
    'workflow': workflowCommand(),
    'record': recordCommand(),
    'tap': actionCommand(),
    'fill': actionCommand(fill: true),
    'scroll': swipeCommand(coordinates: false),
    'screenshot': screenshotCommand(),
    'logs': CliCommand(ArgParser(), noArguments),
    'wait': waitCommand(),
    'swipe': swipeCommand(),
    'connect': CliCommand(ArgParser(), (args) {
      if (args.rest.length != 1) invalid('Usage: connect <uri>');
      return {'uri': args.rest.single};
    }),
    'close': CliCommand(ArgParser(), noArguments),
    'snapshot': CliCommand(ArgParser(), noArguments),
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
  static Json noArguments(ArgResults args) {
    if (args.rest.isNotEmpty) invalid('Unexpected arguments');
    return {};
  }

  String get usage =>
      'Usage: marionette-agent [options] <command>\n${parser.usage}\n\n'
      'Commands: ${definitions.keys.join(', ')}\n'
      'connect <uri> | session list | session show | close | snapshot\n'
      'swipe <ref|selector> <left|right|up|down> [--distance <n>]\n'
      'swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>\n'
      'Directions describe finger movement; verify the result with snapshot.\n'
      'tap <ref|selector> | tap --x <n> --y <n> | fill <ref|selector> <text>\n'
      'scroll <ref|selector> <left|right|up|down> [--distance <n>]\n'
      'scroll uses finger movement direction; reaching content is not guaranteed.\n'
      'screenshot [path] | logs\n'
      'Screenshot destination: explicit path > --screenshot-dir > temporary directory.\n'
      'Screenshot directories must exist; --screenshot-dir must not be a symlink.\n'
      'wait <selector> [--state exists|gone] [--poll-interval <ms>]\n'
      'wait observes only; run snapshot before the next UI operation.\n'
      'record start <path> --platform ios|android|macos --device <id>\n'
      'record stop | record status (no connect required; close finalizes recording)\n'
      'workflow schema [action] | workflow validate <path> | workflow run <path>\n'
      'workflow: --format json|yaml --inputs <path> --inputs-format json|yaml\n'
      'validate --check-inputs checks bindings without connecting. stdin (-) requires format.\n'
      'sensitive forbids defaults; snapshots may reveal values displayed by the app.\n'
      'Workflow stops on failure; completed steps must not be replayed automatically.\n'
      'Selectors: --key <value> | --identifier <value> | --text <value> | --type <value>\n'
      'Common options work before or after commands. Use -- for literal arguments.';

  Invocation parse(
    List<String> arguments, {
    void Function(String? session, bool json)? onOutput,
    void Function(String? command)? onCommand,
  }) {
    final ArgResults args;
    try {
      args = parser.parse(arguments);
    } on ArgParserException catch (error) {
      onCommand?.call(error.commands.firstOrNull);
      CommonOptions.recoverOutput(parser, arguments, error.commands, onOutput);
      invalid('Invalid command syntax');
    } on FormatException {
      invalid('Invalid command syntax');
    }
    onCommand?.call(args.command?.name);
    CommonOptions.reportOutput(args, onOutput);
    CommonOptions.rejectDuplicateOptions(parser, arguments);
    final options = CommonOptions.parse(args);
    if (options.special != null) {
      return Invocation(options, options.special!, {});
    }
    final command = args.command;
    if (command == null) invalid('A command is required');
    return Invocation(
      options,
      command.name!,
      definitions[command.name]!.decode(command),
    );
  }
}

/// Parsed CLI result. Runner records execution start time before parsing.
class Invocation {
  Invocation(this.options, this.command, this.params);
  final CommonOptions options;
  String get session => options.session;
  bool get json => options.json;
  int get timeoutMs => options.timeoutMs;
  final String command;
  final Json params;
  String? get resultSession =>
      command == 'help' ||
          command == 'version' ||
          (command == 'workflow' && params['action'] != 'run') ||
          (command == 'session' && params['action'] == 'list')
      ? null
      : session;
}
