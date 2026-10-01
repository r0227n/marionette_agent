import 'package:args/args.dart';

import '../protocol/protocol.dart';

/// Register ArgParser grammar and conversion from validated args to protocol params.
class CliCommand {
  CliCommand(this.parser, this.decode);
  final ArgParser parser;
  final Json Function(ArgResults) decode;
}

Json noArguments(ArgResults args) {
  if (args.rest.isNotEmpty) invalid('Unexpected arguments');
  return {};
}
