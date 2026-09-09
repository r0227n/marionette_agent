import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/runner.dart';
import 'package:marionette_agent/src/commands/registry.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:marionette_agent/src/session/session_manager.dart';

Future<void> main(List<String> args) async {
  configureDiagnosticLogging();
  if (args.length == 1 && args.single == '--internal-daemon') {
    final registry = CommandRegistry();
    registry.register('count', (context, params) async {
      return context.read((backend) async {
        await backend.inspect();
        return {
          'calls': (backend as FakeBackend).calls
              .where((v) => v == 'inspect')
              .length,
        };
      });
    });
    registry.register('log', (context, params) async {
      Logger('fake-daemon').info('Request handled');
      return {'logged': true};
    });
    await DaemonServer(
      await RuntimeDirectory.prepare(),
      SessionManager(FakeBackend.new, registry),
    ).run();
  } else {
    exitCode = await runCli(
      args,
      parser: CliParser(
        commands: {
          'count': CliCommand(ArgParser(), CliParser.noArguments),
          'log': CliCommand(ArgParser(), CliParser.noArguments),
        },
      ),
    );
  }
}
