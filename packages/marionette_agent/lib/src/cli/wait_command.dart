import 'package:args/args.dart';

import '../backend/backend.dart';
import '../commands/wait.dart';
import '../protocol/protocol.dart';
import 'parser.dart';
import 'target_options.dart';

/// Standalone wait grammar. The root --timeout option owns the total deadline.
CliCommand waitCommand() {
  final parser = ArgParser()
    ..addOption(
      'state',
      defaultsTo: defaultWaitState,
      allowed: const ['exists', 'gone'],
      help: 'Wait until the target exists or is gone',
    )
    ..addOption(
      'poll-interval',
      defaultsTo: '$defaultWaitPollIntervalMs',
      help: 'Milliseconds between observations (50-1000)',
    );
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    if (args.rest.isNotEmpty) {
      invalid(
        'Usage: wait <selector> [--state exists|gone] [--poll-interval <ms>]',
      );
    }
    final pollInterval = int.tryParse(args.option('poll-interval')!);
    if (pollInterval == null) {
      invalid('Poll interval must be an integer from 50 to 1000');
    }
    final request = WaitRequest.parse({
      for (final kind in SelectorKind.values)
        if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
      'state': args.option('state'),
      'pollIntervalMs': pollInterval,
    });
    return request.toJson();
  });
}
