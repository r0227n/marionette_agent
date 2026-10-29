import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/observations.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

CliCommand snapshotCommand() {
  final parser = ArgParser()
    ..addOption('source', allowed: ['flutter', 'native', 'all'])
    ..addFlag('interactive', negatable: false)
    ..addFlag('compact', negatable: false)
    ..addOption('depth');
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    if (args.rest.isNotEmpty) invalid('Snapshot accepts only selector options');
    final params = <String, dynamic>{
      for (final kind in SelectorKind.values)
        if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
    };
    if (args.flag('interactive')) params['interactive'] = true;
    if (args.flag('compact')) params['compact'] = true;
    if (args.option('depth') != null) {
      final depth = int.tryParse(args.option('depth')!);
      if (depth == null || depth < 0) {
        invalid('Depth must be a non-negative integer');
      }
      params['depth'] = depth;
    }
    if (args.wasParsed('source')) params['source'] = args.option('source');
    snapshotFilter(params);
    return params;
  });
}

CliCommand screenshotCommand() => CliCommand(
  ArgParser()
    ..addOption('source', allowed: screenshotSources)
    ..addOption('device'),
  (args) {
    if (args.rest.length > 1) {
      invalid('Usage: screenshot --device <UDID> [path]');
    }
    if (args.rest.isNotEmpty &&
        RegExp(r'^@e[0-9]+$').hasMatch(args.rest.single)) {
      invalid(
        'Screenshot ref/crop targets have been removed; specify an output path',
      );
    }
    final params = <String, Object?>{
      'device': args.option('device'),
      if (args.wasParsed('source')) 'source': args.option('source'),
      if (args.rest.isNotEmpty) 'path': args.rest.single,
    };
    validateScreenshotRequest(params);
    params['device'] = resolveScreenshotDevice(params);
    return params;
  },
);
