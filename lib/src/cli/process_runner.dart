import 'dart:async';
import 'dart:convert';
import 'dart:io';

Duration remaining(DateTime deadline) {
  final duration = deadline.difference(DateTime.now());
  if (duration <= Duration.zero) throw TimeoutException('Process deadline');
  return duration;
}

Future<ProcessResult> runProcessUntil(
  String executable,
  List<String> args,
  DateTime deadline,
) async {
  // Reject expired work before it can create a process or produce side effects.
  remaining(deadline);
  var expired = false;
  final starting = Process.start(executable, args);
  unawaited(
    starting.then((child) {
      if (expired) child.kill(ProcessSignal.sigkill);
    }, onError: (Object _) {}),
  );
  final Process child;
  try {
    child = await starting.timeout(deadline.difference(DateTime.now()));
  } catch (_) {
    expired = true;
    rethrow;
  }
  // Observe all pipe failures immediately, including errors before exitCode.
  // No caller supplies stdin, so EOF must not depend on the child exiting.
  final completion = Future.wait<Object?>([
    child.exitCode,
    utf8.decoder.bind(child.stdout).join(),
    utf8.decoder.bind(child.stderr).join(),
    child.stdin.close(),
  ], eagerError: true);
  try {
    final values = await completion.timeout(
      deadline.difference(DateTime.now()),
    );
    return ProcessResult(
      child.pid,
      values[0] as int,
      values[1] as String,
      values[2] as String,
    );
  } finally {
    child.kill(ProcessSignal.sigkill);
  }
}
