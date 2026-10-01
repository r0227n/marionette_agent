import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/wait_request.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

/// Standalone wait grammar. The root --timeout option owns the total deadline.
CliCommand waitCommand() {
  final parser = ArgParser()
    ..addOption(
      'state',
      defaultsTo: defaultWaitState,
      allowed: waitStates,
      help: 'Wait until the target exists or is gone',
    )
    ..addOption(
      'poll-interval',
      defaultsTo: '$defaultWaitPollIntervalMs',
      help:
          'Milliseconds between observations ($minimumWaitPollIntervalMs-$maximumWaitPollIntervalMs)',
    );
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    if (args.rest.length == 1 &&
        !SelectorKind.values.any((kind) => args.wasParsed(kind.name))) {
      final value = args.rest.single;
      if (value.startsWith('@')) {
        return WaitRequest.parse({
          'ref': value,
          'state': args.option('state'),
          'pollIntervalMs': int.tryParse(args.option('poll-interval')!),
        }).toJson();
      }
      if (args.wasParsed('state') || args.wasParsed('poll-interval')) {
        invalid('Duration wait does not accept target options');
      }
      return WaitRequest.parse({
        'milliseconds': parseDurationMs(value, allowZero: true),
      }).toJson();
    }
    if (args.rest.isNotEmpty) {
      invalid(
        'Usage: wait <selector> [--state exists|gone] [--poll-interval <ms>]',
      );
    }
    final request = WaitRequest.parse({
      for (final kind in SelectorKind.values)
        if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
      'state': args.option('state'),
      'pollIntervalMs': int.tryParse(args.option('poll-interval')!),
    });
    return request.toJson();
  });
}
