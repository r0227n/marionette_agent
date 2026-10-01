import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/swipe.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

/// Shared grammar and primitive for swipe and region scroll.
CliCommand swipeCommand({bool coordinates = true}) {
  final parser = ArgParser()
    ..addOption('distance', help: 'Positive logical pixels (default 200)');
  addSelectorOptions(parser);
  if (coordinates) {
    for (final name in swipeCoordinates) {
      parser.addOption(name, help: 'Non-negative logical pixels');
    }
  }
  return CliCommand(parser, (args) {
    final params = <String, dynamic>{
      for (final name in [
        ...SelectorKind.values.map((k) => k.name),
        'distance',
        if (coordinates) ...swipeCoordinates,
      ])
        if (args.wasParsed(name)) name: args.option(name),
    };
    final coordinateMode = swipeCoordinates.any(params.containsKey);
    if (coordinateMode) {
      if (args.rest.isNotEmpty) {
        invalid('Coordinate swipe does not accept a target or direction');
      }
    } else {
      if (args.rest.isEmpty || args.rest.length > 2) {
        invalid(
          'Usage: ${coordinates ? 'swipe' : 'scroll'} <ref|selector> <left|right|up|down> [--distance <n>]',
        );
      }
      params['direction'] = args.rest.last;
      if (args.rest.length == 2) params['ref'] = args.rest.first;
    }
    SwipeRequest.parse(params, coordinates: coordinates);
    return params;
  });
}
