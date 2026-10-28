import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../../commands/screenshot_request.dart';
import '../command.dart';

CliCommand diffCommand() => CliCommand(
  ArgParser()
    ..addCommand(
      'snapshot',
      ArgParser()..addOption('baseline', mandatory: true),
    )
    ..addCommand(
      'screenshot',
      ArgParser()
        ..addOption('baseline', mandatory: true)
        ..addOption('source', allowed: screenshotSources)
        ..addOption('device')
        ..addOption('output')
        ..addOption('threshold', defaultsTo: '0'),
    ),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty || child == null || child.rest.isNotEmpty) {
      invalid('Usage: diff snapshot|screenshot --baseline <path>');
    }
    final path = child.option('baseline')!;
    if (path.isEmpty) invalid('Baseline path must not be empty');
    if (child.name == 'screenshot') {
      validateScreenshotRequest({
        'device': child.option('device'),
        if (child.wasParsed('source')) 'source': child.option('source'),
      });
    }
    return {
      'action': child.name,
      'baseline': path,
      if (child.name == 'screenshot') ...{
        'device': resolveScreenshotDevice({
          'device': child.option('device'),
          'source': child.option('source'),
        }),
        if (child.wasParsed('source')) 'source': child.option('source'),
        'output': child.option('output'),
        'threshold': parseThreshold(child.option('threshold')!),
      },
    };
  },
);

int parseThreshold(String value) {
  final threshold = int.tryParse(value);
  if (threshold == null || threshold < 0 || threshold > 255) {
    invalid('Threshold must be an integer from 0 to 255');
  }
  return threshold;
}
