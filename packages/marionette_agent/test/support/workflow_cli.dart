import 'dart:io';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/cli/runner.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--internal-daemon') {
    await DaemonServer(
      await RuntimeDirectory.prepare(),
      SessionManager(
        () =>
            FakeBackend()
              ..elements = [ElementInfo(key: 'button', type: 'Button')],
        coreCommands(),
      ),
    ).run();
  } else {
    exitCode = await runCli(args);
  }
}
