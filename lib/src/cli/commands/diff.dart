import 'dart:io';

import 'package:args/args.dart';
// ignore: implementation_imports
// ignore: implementation_imports
// ignore: implementation_imports

import '../../protocol/protocol.dart';
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
    if (child.name == 'screenshot' &&
        (child.option('device') == null || child.option('device')!.isEmpty)) {
      invalid('diff screenshot requires --device <pairing-file>');
    }
    return {
      'action': child.name,
      'baseline': path,
      if (child.name == 'screenshot') ...{
        'device': File(child.option('device')!).absolute.path,
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
