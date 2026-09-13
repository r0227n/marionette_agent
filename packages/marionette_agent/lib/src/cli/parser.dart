import 'dart:io';

import 'package:args/args.dart';

import 'common_options.dart';
import '../protocol/protocol.dart';
import '../commands/swipe.dart';
import '../commands/actions.dart';
import '../commands/observations.dart';
import 'workflow_command.dart';
import 'record_command.dart';
import 'wait_command.dart';
import 'get_command.dart';
import '../commands/is_visible.dart';

/// Register ArgParser grammar and conversion from validated args to protocol params.
class CliCommand {
  CliCommand(this.parser, this.decode);
  final ArgParser parser;
  final Json Function(ArgResults) decode;
}

/// args owns tokenization, subcommands, option values, -- and usage rendering.
/// Only the product's duplicate-option and value constraints are custom.
class CliParser {
  CliParser({
    Map<String, CliCommand> commands = const {},
    Map<String, String>? environment,
  }) : parser = CommonOptions.createParser(
         environment ?? Platform.environment,
       ) {
    definitions.addAll(commands);
    for (final entry in definitions.entries) {
      parser.addCommand(entry.key, entry.value.parser);
    }
  }
  final ArgParser parser;
  final definitions = <String, CliCommand>{
    'doctor': CliCommand(ArgParser()..addOption('probe-uri'), (args) {
      if (args.rest.isNotEmpty) invalid('Usage: doctor [--probe-uri <uri>]');
      return {'probeUri': args['probe-uri']};
    }),
    'workflow': workflowCommand(),
    'record': recordCommand(),
    'tap': actionCommand(),
    'fill': actionCommand(fill: true),
    'scroll': swipeCommand(coordinates: false),
    'screenshot': screenshotCommand(),
    'logs': CliCommand(ArgParser(), noArguments),
    'wait': waitCommand(),
    'get': getCommand(),
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
  static Json noArguments(ArgResults args) {
    if (args.rest.isNotEmpty) invalid('Unexpected arguments');
    return {};
  }

  String get usage =>
      'Usage: marionette-agent [options] <command>\n${parser.usage}\n\n'
      'Commands: ${definitions.keys.join(', ')}\n'
      'doctor [--probe-uri <uri>] (read-only; no connection required)\n'
      'snapshot [--key <value> | --identifier <value> | --text <value> | --type <value>]\n'
      'Snapshot filters observed values; zero/multiple matches are valid. Full observation determines ref safety.\n'
      'get text|box <ref|selector> | get count <selector>\n'
      'get preserves refs; box uses Flutter logical pixels; missing values are null.\n'
      'connect <uri> | session list | session show | close [--all] | snapshot\n'
      'close --all stops all sessions; cannot combine with --session. Apps keep running.\n'
      'swipe <ref|selector> <left|right|up|down> [--distance <n>]\n'
      'swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>\n'
      'Directions describe finger movement; verify the result with snapshot.\n'
      'tap <ref|selector> | tap --x <n> --y <n> | fill <ref|selector> <text>\n'
      'scroll <ref|selector> <left|right|up|down> [--distance <n>]\n'
      'scroll uses finger movement direction; reaching content is not guaranteed.\n'
      'screenshot [--annotate] [path] | logs\n'
      '  --annotate requires a valid snapshot and an opt-in mapped screenshot provider.\n'
      'is visible <ref|selector> (true, false, or unknown; preserves refs)\n'
      'Screenshot extensions: .png or .jpg/.jpeg; missing extension is appended.\n'
      'Multiple images: name-1.ext, name-2.ext; existing files are refused.\n'
      'Path omitted: private screen.png/screen.jpg; conversion uses --timeout.\n'
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
      'Common options work before or after commands. Use -- for literal arguments.\n'
      'Session/timeout validate only the selected CLI, environment or default value.\n'
      'Empty or invalid selected values are INVALID_ARGUMENT; overridden environment values are ignored.';

  Invocation parse(
    List<String> arguments, {
    void Function(String? session, bool json)? onOutput,
    void Function(String? command)? onCommand,
    void Function(bool)? onDebug,
  }) {
    final ArgResults args;
    try {
      args = parser.parse(arguments);
    } on ArgParserException catch (error) {
      onCommand?.call(error.commands.firstOrNull);
      CommonOptions.recoverOutput(
        parser,
        arguments,
        error.commands,
        onOutput,
        onDebug,
      );
      invalid('Invalid command syntax');
    } on FormatException {
      invalid('Invalid command syntax');
    }
    onCommand?.call(args.command?.name);
    CommonOptions.reportOutput(args, onOutput, onDebug);
    CommonOptions.rejectDuplicateOptions(parser, arguments);
    final options = CommonOptions.parse(args);
    if (options.special != null) {
      return Invocation(options, options.special!, {});
    }
    final command = args.command;
    if (command == null) invalid('A command is required');
    final params = definitions[command.name]!.decode(command);
    if (command.name == 'screenshot' && params['path'] is String) {
      params['path'] = options.screenshotFormat.destinationPath(
        params['path'] as String,
      );
    }
    if (command.name == 'close' &&
        params['all'] == true &&
        args.wasParsed('session')) {
      invalid('close --all cannot be combined with --session');
    }
    return Invocation(options, command.name!, params);
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
          command == 'doctor' ||
          command == 'version' ||
          (command == 'workflow' && params['action'] != 'run') ||
          (command == 'session' && params['action'] == 'list') ||
          (command == 'close' && params['all'] == true)
      ? null
      : session;
}
