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
import '../commands/interactions.dart';
import '../commands/find.dart';
import 'diff_command.dart';
import 'config_file.dart';
import 'state_command.dart';
import 'install_command.dart';
import 'batch_command.dart';
import 'skills_command.dart';
import '../commands/keyboard.dart';
import '../commands/drag.dart';

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
  }) : environment = environment ?? Platform.environment,
       parser = CommonOptions.createParser(
         environment ?? Platform.environment,
       ) {
    definitions.addAll(commands);
    for (final entry in definitions.entries) {
      parser.addCommand(entry.key, entry.value.parser);
    }
  }
  final ArgParser parser;
  final Map<String, String> environment;
  final definitions = <String, CliCommand>{
    'skills': skillsCommand(),
    'device': CliCommand(
      ArgParser()..addCommand(
        'list',
        ArgParser()..addOption(
          'platform',
          allowed: ['ios', 'android'],
          defaultsTo: 'ios',
        ),
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
  static Json noArguments(ArgResults args) {
    if (args.rest.isNotEmpty) invalid('Unexpected arguments');
    return {};
  }

  String get usage =>
      'Usage: marionette-agent [options] <command>\n${parser.usage}\n\n'
      'Commands: ${definitions.keys.join(', ')}\n'
      'skills [list] | skills get <name> [name...] [--full] | skills get --all [--full]\n'
      'skills path [name] | skills --help (bundled guides; no download or connection)\n'
      'Start with marionette-agent skills get core; use --full for references and templates.\n'
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
      'Screenshot destination: explicit path > --screenshot-dir > temporary directory.\n'
      'Screenshot directories must exist; --screenshot-dir must not be a symlink.\n'
      'is visible <ref|selector> (true, false, or unknown; preserves refs)\n'
      'Screenshot extensions: .png or .jpg/.jpeg; missing extension is appended.\n'
      'Multiple images: name-1.ext, name-2.ext; existing files are refused.\n'
      'Path and directory omitted: private screen.png/screen.jpg; conversion uses --timeout.\n'
      'wait <selector> [--state exists|gone] [--poll-interval <ms>]\n'
      'wait observes only; run snapshot before the next UI operation.\n'
      'record start <path> --platform ios|android|macos|web --device <id>\n'
      'web: --device display:<index>@ws://127.0.0.1:<port>/devtools/page/<id> (.mov; whole display, visible Chrome on macOS)\n'
      'record stop | record status (no connect required; close finalizes recording)\n'
      'workflow schema [action] | workflow validate <path> | workflow run <path>\n'
      'workflow: --format json|yaml --inputs <path> --inputs-format json|yaml\n'
      'validate --check-inputs checks bindings without connecting. stdin (-) requires format.\n'
      'sensitive forbids defaults; snapshots may reveal values displayed by the app.\n'
      'Workflow stops on failure; completed steps must not be replayed automatically.\n'
      'Selectors: --key <value> | --identifier <value> | --text <value> | --type <value>\n'
      'Common options work before or after commands. Use -- for literal arguments.\n'
      'Session/timeout validate only the selected CLI, environment or default value.\n'
      'Empty or invalid selected values are INVALID_ARGUMENT; overridden environment values are ignored.\n'
      'Additional Flutter commands (see docs/ja/cli-parity.ja.md):\n'
      'snapshot --interactive --compact --depth <n> | get value | is enabled|checked\n'
      'find role|label|placeholder|text|key|identifier|type <value> [action] [input] [--exact] [--name <label>]\n'
      'find first|last <selector> [action] | find nth <index> <selector> [action]\n'
      'click|dblclick|focus|hover|check|uncheck|scrollintoview <ref|selector>\n'
      'type|select <ref|selector> <input> | press <key-combination> | keydown|keyup <key>\n'
      'keyboard press|type|inserttext <input> | clipboard read|write <text>|copy|paste\n'
      'drag <from-ref> <to-ref> | drag --from-key <key> --to-key <key>\n'
      'wait <milliseconds|ref> | screenshot <ref|selector> [path]\n'
      'diff snapshot|screenshot --baseline <path> [--threshold <0-255> --output <path>]\n'
      'record restart <path> --platform <platform> --device <id> | record start/restart --fps <1-60>\n'
      'device list [--platform ios|android] | batch <JSON-file|->\n'
      'state save|load <path> (connection only) | confirm|deny <confirmation-id>\n'
      'doctor --quick|--offline|--fix | install|upgrade [--source <package-directory>] <bin-directory>';

  Invocation parse(
    List<String> arguments, {
    void Function(String? session, bool json)? onOutput,
    void Function(String? command)? onCommand,
    void Function(bool)? onDebug,
  }) {
    final ArgResults args;
    try {
      final selected = parser.parse(arguments);
      CommonOptions.reportOutput(selected, onOutput, onDebug);
      final defaults = configArguments(parser, selected, environment);
      arguments = [...defaults, ...arguments];
      args = defaults.isEmpty ? selected : parser.parse(arguments);
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
      if (options.special == 'help' && args.command?.name == 'skills') {
        return Invocation(options, 'skills', {'action': 'help'});
      }
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
          command == 'skills' ||
          command == 'doctor' ||
          command == 'device' ||
          command == 'install' ||
          command == 'upgrade' ||
          command == 'version' ||
          (command == 'workflow' && params['action'] != 'run') ||
          (command == 'session' && params['action'] == 'list') ||
          (command == 'close' && params['all'] == true)
      ? null
      : session;
}
