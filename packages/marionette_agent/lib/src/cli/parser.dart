import 'package:args/args.dart';

import '../protocol/protocol.dart';

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
  final parser = ArgParser()
    ..addOption('session', defaultsTo: 'default', help: 'Session name')
    ..addFlag('json', negatable: false, help: 'One JSON result on stdout')
    ..addOption(
      'timeout',
      defaultsTo: '30000',
      help: 'Positive deadline in milliseconds',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('version', negatable: false, help: 'Show version');
  final definitions = <String, CliCommand>{
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
      'Common options work before or after commands. Use -- for literal arguments.';

  Invocation parse(
    List<String> arguments, {
    void Function(String? session, bool json)? onOutput,
  }) {
    final ArgResults args;
    try {
      args = parser.parse(arguments);
    } on FormatException {
      invalid('Invalid command syntax');
    }
    final parsedName = args.option('session')!;
    final independent =
        args.flag('help') ||
        args.flag('version') ||
        (args.command?.name == 'session' &&
            args.command?.command?.name == 'list');
    onOutput?.call(
      independent ||
              !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(parsedName)
          ? null
          : parsedName,
      args.flag('json'),
    );
    _rejectDuplicateOptions(arguments);
    final session = args.option('session')!;
    validateSession(session);
    final timeout = int.tryParse(args.option('timeout')!);
    if (timeout == null || timeout <= 0) {
      invalid('Timeout must be a positive integer');
    }
    if (args.flag('help') && args.flag('version')) {
      invalid('Choose help or version');
    }
    final special = args.flag('help')
        ? 'help'
        : args.flag('version')
        ? 'version'
        : null;
    if (special != null) {
      return Invocation(session, args.flag('json'), timeout, special, {});
    }
    final command = args.command;
    if (command == null) invalid('A command is required');
    return Invocation(
      session,
      args.flag('json'),
      timeout,
      command.name!,
      definitions[command.name]!.decode(command),
    );
  }

  void _rejectDuplicateOptions(List<String> arguments) {
    var grammar = parser;
    final seen = <String>{};
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg == '--') break;
      if (grammar.commands[arg] case final ArgParser child) {
        grammar = child;
        continue;
      }
      final name = arg.startsWith('--')
          ? arg.substring(2).split('=').first
          : arg == '-h'
          ? 'help'
          : null;
      final option = grammar.options[name] ?? parser.options[name];
      if (option == null) {
        if (RegExp(r'^-h+$').hasMatch(arg)) {
          for (var j = 1; j < arg.length; j++) {
            if (!seen.add('help')) invalid('Duplicate option');
          }
        }
        continue;
      }
      if (!seen.add(option.name)) invalid('Duplicate option');
      if (option.isFlag && arg.contains('=')) {
        invalid('Flag does not accept a value');
      }
      if (!option.isFlag && !arg.contains('=')) i++;
    }
  }
}

/// Parsed CLI result. Runner records execution start time before parsing.
class Invocation {
  Invocation(
    this.session,
    this.json,
    this.timeoutMs,
    this.command,
    this.params,
  );
  final String session;
  final bool json;
  final int timeoutMs;
  final String command;
  final Json params;
  String? get resultSession =>
      command == 'help' ||
          command == 'version' ||
          (command == 'session' && params['action'] == 'list')
      ? null
      : session;
}
