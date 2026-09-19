import 'dart:io';

import 'package:args/args.dart';

import '../protocol/protocol.dart';
import '../protocol/command_scope.dart';
import 'command.dart';
import 'commands/catalog.dart';
import 'common_options.dart';
import 'config_file.dart';
import 'help.dart';

export 'command.dart';

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
  final definitions = builtInCommands();
  String get usage => cliUsage(parser, definitions.keys);

  Invocation parse(
    List<String> arguments, {
    void Function(String? session, bool json)? onOutput,
    void Function(String? command)? onCommand,
    void Function(bool)? onDebug,
  }) {
    final ArgResults args;
    try {
      final selected = parser.parse(arguments);
      onCommand?.call(selected.command?.name);
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
      usesSession(command, action: params['action'], all: params['all'] == true)
      ? session
      : null;
}
