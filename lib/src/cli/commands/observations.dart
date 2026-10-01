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
  final parser = ArgParser()..addFlag('annotate', negatable: false);
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    final rest = args.rest.toList();
    final params = <String, Object?>{};
    for (final kind in SelectorKind.values) {
      if (args.wasParsed(kind.name)) params[kind.name] = args.option(kind.name);
    }
    if (rest.isNotEmpty && rest.first.startsWith('@')) {
      params['ref'] = rest.removeAt(0);
    }
    if (rest.length > 1 || (rest.isNotEmpty && rest.single.isEmpty)) {
      invalid('Usage: screenshot [ref|selector] [--annotate] [path]');
    }
    if (rest.isNotEmpty) params['path'] = rest.single;
    if (args.flag('annotate')) params['annotate'] = true;
    screenshotTarget(params);
    return params;
  });
}
