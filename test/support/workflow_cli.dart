import 'dart:io';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/runner.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';

import 'fake_backend.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--internal-daemon') {
    await DaemonServer(
      await RuntimeDirectory.prepare(),
      SessionManager(
        () =>
            FakeBackend()
              ..elements = [ElementInfo(key: 'button', type: 'Button')],
        coreCommands(),
      ),
      idleTimeoutMs: CommonOptions.daemonIdle(args),
    ).run();
  } else {
    exitCode = await runCli(args);
  }
}
