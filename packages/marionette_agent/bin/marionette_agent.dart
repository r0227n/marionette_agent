import 'package:marionette_agent/src/cli/common_options.dart';

import 'dart:io';

import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/cli/runner.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:marionette_agent/src/session/session_manager.dart';

Future<void> main(List<String> args) async {
  configureDiagnosticLogging();
  if (args.isNotEmpty && args.first == '--internal-daemon') {
    try {
      await DaemonServer(
        await RuntimeDirectory.prepare(),
        SessionManager(MarionetteBackend.new, coreCommands()),
        idleTimeoutMs: CommonOptions.daemonIdle(args),
      ).run();
    } catch (_) {
      stderr.writeln('Daemon startup failed');
      exitCode = 1;
    }
  } else {
    exitCode = await runCli(args);
  }
}
