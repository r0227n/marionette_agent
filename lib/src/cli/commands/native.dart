import 'package:args/args.dart';

import '../../commands/native_request.dart';
import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand nativeCommand() {
  ArgParser device() => ArgParser()
    ..addOption('platform', allowed: ['ios', 'android'])
    ..addOption('device');
  return CliCommand(
    ArgParser()
      ..addCommand('snapshot', device())
      ..addCommand('screenshot', device())
      ..addCommand(
        'tap',
        device()
          ..addOption('text')
          ..addOption('identifier')
          ..addOption('type')
          ..addOption('x')
          ..addOption('y'),
      )
      ..addCommand(
        'swipe',
        device()
          ..addOption('start-x')
          ..addOption('start-y')
          ..addOption('end-x')
          ..addOption('end-y'),
      ),
    (args) {
      final child = args.command;
      if (child == null || args.rest.isNotEmpty) {
        invalid('Usage: native snapshot|tap|swipe|screenshot');
      }
      final params = <String, Object?>{
        'action': child.name,
        'platform': child.option('platform'),
        'device': child.option('device'),
      };
      if (child.rest.length >
          (['tap', 'screenshot'].contains(child.name) ? 1 : 0)) {
        invalid();
      }
      if (child.rest.isNotEmpty) {
        params[child.name == 'tap' ? 'ref' : 'path'] = child.rest.single;
      }
      if (child.name == 'tap') {
        for (final key in ['text', 'identifier', 'type']) {
          if (child.wasParsed(key)) params[key] = child.option(key);
        }
      }
      for (final entry
          in (child.name == 'tap'
                  ? {'x': 'x', 'y': 'y'}
                  : child.name == 'swipe'
                  ? {
                      'start-x': 'startX',
                      'start-y': 'startY',
                      'end-x': 'endX',
                      'end-y': 'endY',
                    }
                  : <String, String>{})
              .entries) {
        if (child.wasParsed(entry.key)) {
          params[entry.value] = double.tryParse(child.option(entry.key)!);
        }
      }
      validateNative(params);
      return params;
    },
  );
}
