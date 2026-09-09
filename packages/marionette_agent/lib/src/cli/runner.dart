import 'dart:io';
import 'dart:math';

import '../daemon/client.dart';
import '../daemon/runtime.dart';
import '../protocol/protocol.dart';
import 'parser.dart';
import 'artifact_writer.dart';
import 'renderer.dart';

/// Handles parsing, one-shot IPC, and final stdout response, then returns exit code.
Future<int> runCli(
  List<String> args, {
  CliParser? parser,
  List<String>? launchCommand,
}) async {
  final started = DateTime.now();
  var json = args.takeWhile((arg) => arg != '--').contains('--json');
  String? session = 'default';
  Result result;
  final cliParser = parser ?? CliParser();
  try {
    final invocation = cliParser.parse(
      args,
      onOutput: (name, useJson) {
        session = name;
        json = useJson;
      },
    );
    json = invocation.json;
    session = invocation.resultSession;
    if (invocation.command == 'help') {
      result = Result.success(null, {'help': cliParser.usage});
    } else if (invocation.command == 'version') {
      result = Result.success(null, {'version': version});
    } else {
      final runtime = await RuntimeDirectory.prepare();
      result = await DaemonClient(runtime, launchCommand: launchCommand).send(
        Request(
          requestId: '$pid-${Random.secure().nextInt(1 << 32)}',
          session: invocation.session,
          command: invocation.command,
          params: invocation.params,
          deadline: started.add(Duration(milliseconds: invocation.timeoutMs)),
        ),
      );
      if (invocation.command == 'screenshot' && result.error == null) {
        result = Result.success(
          session,
          await saveScreenshots(
            result.data!,
            invocation.params['path'] as String?,
            started.add(Duration(milliseconds: invocation.timeoutMs)),
          ),
        );
      }
    }
  } on AgentError catch (error) {
    result = Result.failure(session, error);
  } catch (_) {
    result = Result.failure(
      session,
      const AgentError('INTERNAL_ERROR', 'CLI failed'),
    );
  }
  stdout.writeln(render(result, json: json));
  if (!json && result.error?.code == 'INVALID_ARGUMENT') {
    stdout.writeln(cliParser.usage);
  }
  return result.exitCode;
}
