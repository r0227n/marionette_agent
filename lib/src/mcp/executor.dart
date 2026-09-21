import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../cli/parser.dart';
import '../daemon/client.dart';
import '../protocol/protocol.dart';

class McpExecution {
  McpExecution(this.response, this.exitCode);
  final Json response;
  final int exitCode;
}

/// Executes exactly one CLI process per call, preserving the existing CLI/IPC
/// contract. Child stdin is closed; neither a shell nor MCP stdin is inherited.
class McpExecutor {
  McpExecutor({List<String>? launchCommand})
    : launchCommand = launchCommand ?? DaemonClient.defaultLaunchCommand();

  final List<String> launchCommand;
  final _children = <Process>{};
  bool _closed = false;

  Future<McpExecution> run(List<String> args) async {
    Invocation invocation;
    String? session;
    try {
      invocation = CliParser().parse(
        args,
        onOutput: (name, _) => session = name,
      );
    } on AgentError catch (error) {
      final result = Result.failure(session, error);
      return McpExecution(result.toJson(), result.exitCode);
    }
    final deadline = DateTime.now().add(
      Duration(milliseconds: invocation.timeoutMs) + const Duration(seconds: 5),
    );
    Process? process;
    Future<List<Object?>>? completion;
    try {
      if (_closed) throw const AgentError('IO_ERROR', 'MCP server is closing');
      process = await Process.start(launchCommand.first, [
        ...launchCommand.skip(1),
        ...args,
      ]);
      _children.add(process);
      // A shutdown can race Process.start. Only kill a process we own.
      if (_closed) process.kill(ProcessSignal.sigkill);
      completion = Future.wait<Object?>([
        _capture(process.stdout, process),
        // Diagnostics already undergo the CLI's redaction. Discard them here
        // so subprocess failures can never leak raw diagnostics into MCP.
        process.stderr.drain<void>(),
        process.exitCode,
        process.stdin.close(),
      ]);
      final values = await completion.timeout(
        deadline.difference(DateTime.now()),
      );
      final response = jsonDecode(values[0] as String);
      if (response is! Map<String, Object?>) throw const FormatException();
      // Validate the envelope before exposing any subprocess output.
      final result = Result.fromJson(response);
      return McpExecution(result.toJson(), values[2] as int);
    } catch (error) {
      process?.kill(ProcessSignal.sigkill);
      if (completion != null) {
        try {
          await completion;
        } catch (_) {
          /* Drain owned pipes. */
        }
      }
      final result = Result.failure(
        invocation.resultSession,
        AgentError(
          error is TimeoutException ? 'TIMEOUT' : 'IO_ERROR',
          error is TimeoutException
              ? 'MCP CLI deadline exceeded'
              : 'MCP CLI execution failed',
          outcome: process == null ? Outcome.notSent : Outcome.unknown,
          hint: process == null
              ? null
              : 'Observe the app before deciding whether to retry',
        ),
      );
      return McpExecution(result.toJson(), result.exitCode);
    } finally {
      if (process != null) _children.remove(process);
    }
  }

  Future<String> _capture(Stream<List<int>> source, Process process) async {
    final bytes = BytesBuilder(copy: false);
    var overflow = false;
    await for (final chunk in source) {
      if (!overflow && bytes.length + chunk.length <= 64 * 1024 * 1024) {
        bytes.add(chunk);
      } else if (!overflow) {
        overflow = true;
        process.kill(ProcessSignal.sigkill);
      }
    }
    if (overflow) throw const FormatException('CLI output limit exceeded');
    return utf8.decode(bytes.takeBytes());
  }

  Future<void> close() async {
    _closed = true;
    final children = _children.toList();
    for (final child in children) {
      child.kill(ProcessSignal.sigkill);
    }
    await Future.wait(children.map((child) => child.exitCode));
  }
}
