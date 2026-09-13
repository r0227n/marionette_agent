import 'dart:io';

import 'package:args/args.dart';

import '../protocol/protocol.dart';
import '../recording/record_service.dart';
import 'parser.dart';

CliCommand recordCommand() => CliCommand(
  ArgParser()
    ..addCommand(
      'restart',
      ArgParser()
        ..addOption('platform')
        ..addOption('device')
        ..addOption('fps'),
    )
    ..addCommand(
      'start',
      ArgParser()
        ..addOption('platform')
        ..addOption('device')
        ..addOption('fps'),
    )
    ..addCommand('stop')
    ..addCommand('status'),
  (args) {
    if (args.rest.isNotEmpty) invalid('Usage: record start|stop|status');
    final action = args.command;
    if (action == null) invalid('Usage: record start|stop|status');
    if (action.name == 'start' || action.name == 'restart') {
      if (action.rest.length != 1 || action.rest.single.trim().isEmpty) {
        invalid(
          'Usage: record start <path> --platform <platform> --device <id>',
        );
      }
      if (action.option('platform') == null ||
          action.option('device') == null) {
        invalid('record start requires --platform and --device');
      }
      final params = <String, Object?>{
        'action': action.name,
        if (action.wasParsed('fps')) 'fps': int.tryParse(action.option('fps')!),
        'platform': action.option('platform'),
        'device': action.option('device'),
        'path': File(action.rest.single).absolute.path,
      };
      validateRecordStart(params);
      return params;
    }
    if (action.rest.isNotEmpty) invalid('Unexpected recording arguments');
    return {'action': action.name};
  },
);
