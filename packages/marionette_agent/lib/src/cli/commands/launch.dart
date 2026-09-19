import 'dart:io';

import 'package:args/args.dart';
import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand launchCommand() => CliCommand(
  ArgParser()
    ..addOption(
      'platform',
      allowed: ApplicationPlatform.values.map((p) => p.name),
    )
    ..addOption(
      'flutter',
      help: 'Flutter executable (default: flutter on daemon PATH)',
    )
    ..addOption(
      'target',
      help: 'Dart entrypoint relative to project (default: lib/main.dart)',
    )
    ..addOption('device-type', help: 'iOS simulator device type identifier')
    ..addOption('runtime', help: 'iOS simulator runtime identifier')
    ..addOption('avd', help: 'Existing Android AVD name')
    ..addOption('port', help: 'Unused even emulator port, 5554..5682'),
  (args) {
    if (args.rest.length != 1) {
      invalid(
        'Usage: launch <project> --platform tester|ios|android|macos|web',
      );
    }
    final params = <String, Object?>{
      'project': Directory(args.rest.single).absolute.path,
      'platform': args.option('platform'),
      for (final name in ['flutter', 'target', 'runtime', 'avd'])
        if (args.wasParsed(name)) name: args.option(name),
      if (args.wasParsed('device-type'))
        'deviceType': args.option('device-type'),
      if (args.wasParsed('port'))
        'port': int.tryParse(args.option('port')!) ?? -1,
    };
    if (params['flutter'] is String &&
        (params['flutter'] as String).contains('/')) {
      params['flutter'] = File(params['flutter'] as String).absolute.path;
    }
    try {
      LaunchOptions.fromJson(params);
    } on PlatformException catch (e) {
      throw AgentError(e.code, e.message, hint: e.hint);
    }
    return params;
  },
);
