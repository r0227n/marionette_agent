import 'dart:io';

import 'package:args/args.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/runner.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:marionette_agent/src/snapshot/snapshot_service.dart';

/// Test-only CLI used as a registration example for A06.
/// Verifies a single dispatch through the shared base path, not the production tap command (B01).
Future<void> main(List<String> args) async {
  configureDiagnosticLogging();
  if (args.length == 1 && args.single == '--internal-daemon') {
    final commands = coreCommands()
      ..register('verify-tap', (context, params) {
        if (params.length != 1 || params['ref'] is! String) invalid();
        return context.performTarget(
          RefQuery(params['ref'] as String),
          (backend, selector) => backend.tap(ElementTarget(selector)),
        );
      });
    await DaemonServer(
      await RuntimeDirectory.prepare(),
      SessionManager(MarionetteBackend.new, commands),
    ).run();
  } else {
    exitCode = await runCli(
      args,
      parser: CliParser(
        commands: {
          'verify-tap': CliCommand(ArgParser(), (parsed) {
            if (parsed.rest.length != 1) invalid('Usage: verify-tap <ref>');
            return {'ref': RefQuery(parsed.rest.single).ref};
          }),
        },
      ),
    );
  }
}
