import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../marionette_agent_platform_interface.dart';

void checkRecordingDeadline(DateTime deadline) {
  if (!deadline.isAfter(DateTime.now())) {
    throw const PlatformException(
      'TIMEOUT',
      'Recording request deadline exceeded',
    );
  }
}

Future<Process> spawnRecordingProcess(
  String executable,
  List<String> arguments,
) async {
  try {
    return await Process.start(executable, arguments);
  } on ProcessException {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'Recording tool unavailable',
      hint: 'Install Xcode / Android platform-tools as appropriate.',
    );
  }
}

Future<String> runRecordingCommand(
  String executable,
  List<String> args,
  DateTime deadline, {
  bool allowFailure = false,
}) async {
  checkRecordingDeadline(deadline);
  final process = await spawnRecordingProcess(executable, args);
  return consumeRecordingCommand(process, deadline, allowFailure: allowFailure);
}

/// Internal process-output seam; the deadline covers exit and both pipes.
Future<String> consumeRecordingCommand(
  Process process,
  DateTime deadline, {
  bool allowFailure = false,
}) async {
  final output = StringBuffer();
  final outputDone = process.stdout.transform(utf8.decoder).forEach((text) {
    if (output.length < 1024 * 1024) output.write(text);
  });
  final errors = process.stderr.drain<void>();
  // Install handlers on every future before waiting for process termination.
  final completed = Future.wait<Object?>([
    process.exitCode,
    outputDone,
    errors,
  ], eagerError: true);
  try {
    final results = await completed.timeout(
      deadline.difference(DateTime.now()),
    );
    if (results.first != 0 && !allowFailure) {
      throw const PlatformException(
        'IO_ERROR',
        'Platform recording command failed',
        hint: 'Check device connectivity, available storage and recording permissions.',
      );
    }
    return output.toString();
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    throw const PlatformException(
      'TIMEOUT',
      'Platform recording command timed out',
    );
  } catch (_) {
    process.kill(ProcessSignal.sigkill);
    rethrow;
  }
  // Do not wait for pipe closure after a timeout or stream failure. Future.wait
  // still consumes late failures, even when an inherited pipe remains open.
}

class ProcessRecording implements RecordingHandle {
  ProcessRecording(this.process, {this.failureHint}) {
    _stdoutDone = _consume(process.stdout);
    _stderrDone = _consume(process.stderr);
    ended = Future.wait([
      process.exitCode.then((code) {
        exitCode = code;
      }),
      _stdoutDone,
      _stderrDone,
    ]).then((_) {});
    unawaited(ended.catchError((Object _) {}));
  }
  final Process process;
  final String? failureHint;
  final _lines = <String>[];
  late final Future<void> _stdoutDone, _stderrDone;
  @override
  late final Future<void> ended;
  int? exitCode;
  @override
  bool get isRunning => exitCode == null;
  bool signalLocal = true;
  void Function(String)? onLine;
  Future<void> Function()? beforeStop, afterStop, beforeAbort;
  bool _aborted = false;
  Future<void>? _stopping;

  Future<void> _consume(Stream<List<int>> stream) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (_lines.length < 100) _lines.add(line);
      onLine?.call(line);
    }
  }

  void checkAlive() {
    if (exitCode != null) {
      throw PlatformException(
        'IO_ERROR',
        'Screen recorder exited before capture was ready',
        hint: failureHint,
      );
    }
  }

  Future<void> waitForLine(String text, DateTime deadline) async {
    while (!_lines.any((line) => line.contains(text))) {
      checkAlive();
      checkRecordingDeadline(deadline);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    checkAlive();
  }

  @override
  Future<void> stop() => _stopping ??= _stop();

  @override
  Future<void> abort() async {
    _aborted = true;
    // Stop the host process immediately, even if the remote device is offline.
    process.kill(ProcessSignal.sigkill);
    await beforeAbort?.call();
  }

  Future<void> _stop() async {
    try {
      if (exitCode == null) {
        await beforeStop?.call();
        if (signalLocal) process.kill(ProcessSignal.sigint);
      }
      await ended.timeout(const Duration(seconds: 15));
      // Some tools report SIGINT exit codes even after normal finalization.
      if (![0, 130, -2].contains(exitCode)) {
        throw PlatformException(
          'IO_ERROR',
          'Screen recording failed',
          hint: failureHint,
        );
      }
      if (_aborted) {
        throw const PlatformException('TIMEOUT', 'Recording shutdown expired');
      }
      await afterStop?.call();
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      try {
        await ended.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // RecordingManager retains the device reservation until ended settles.
      }
      throw const PlatformException(
        'TIMEOUT',
        'Screen recorder did not finalize',
      );
    } finally {
      if (exitCode == null) process.kill(ProcessSignal.sigkill);
    }
  }
}
