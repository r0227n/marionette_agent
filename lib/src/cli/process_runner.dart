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
  var expired = false;
  final starting = Process.start(executable, args);
  unawaited(
    starting.then((child) {
      if (expired) child.kill(ProcessSignal.sigkill);
    }, onError: (Object _) {}),
  );
  final Process child;
  try {
    child = await starting.timeout(remaining(deadline));
  } finally {
    expired = true;
  }
  final output = utf8.decoder.bind(child.stdout).join();
  final error = utf8.decoder.bind(child.stderr).join();
  try {
    final code = await child.exitCode.timeout(remaining(deadline));
    return ProcessResult(
      child.pid,
      code,
      await output.timeout(remaining(deadline)),
      await error.timeout(remaining(deadline)),
    );
  } finally {
    child.kill(ProcessSignal.sigkill);
  }
}
