import 'dart:io';

import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/observations.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

CliCommand snapshotCommand() {
  final parser = ArgParser()
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
    snapshotFilter(params);
    return params;
  });
}

CliCommand screenshotCommand() {
  final parser = ArgParser()
    ..addOption('platform', allowed: ['android'], defaultsTo: 'android')
    ..addOption('device')
    ..addOption('display');
  return CliCommand(parser, (args) {
    if (args.rest.length > 1 ||
        (args.rest.isNotEmpty &&
            (args.rest.single.isEmpty || args.rest.single.startsWith('@')))) {
      invalid('Usage: screenshot [path] --device <pairing-file>');
    }
    final params = <String, Object?>{
      'platform': 'android',
      'device': args.option('device'),
      if (args.wasParsed('display')) 'display': args.option('display'),
      if (args.rest.isNotEmpty) 'path': args.rest.single,
    };
    screenshotTarget(params);
    params['device'] = File(params['device'] as String).absolute.path;
    return params;
  });
}
