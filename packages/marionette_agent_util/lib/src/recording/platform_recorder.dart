import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'recorder.dart';
import 'frame_rate_recorder.dart';
import 'web_recorder.dart';
import '../platform_exception.dart';

/// All OS commands, device checks and process signaling live in this package.
class PlatformScreenRecorder implements ScreenRecorder {
  const PlatformScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    if (target.fps != null) {
      return startAtFrameRate(this, target, stagingPath, deadline);
    }
    switch (target.platform) {
      case RecordingPlatform.web:
        return WebScreenRecorder(this).start(target, stagingPath, deadline);
      case RecordingPlatform.linux:
      case RecordingPlatform.windows:
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'Screen recording is not implemented for this platform',
        );
      case RecordingPlatform.ios:
        if (!Platform.isMacOS) {
          _unsupported('iOS Simulator requires macOS/Xcode');
        }
        final devices = jsonDecode(
          await _run('xcrun', [
            'simctl',
            'list',
            'devices',
            'booted',
            '--json',
          ], deadline),
        ) as Map<String, dynamic>;
        final available = (devices['devices'] as Map).values
            .expand((value) => value as List)
            .any(
              (value) =>
                  value['udid'] == target.device && value['state'] == 'Booted',
            );
        if (!available) {
          _unsupported('The selected iOS Simulator is not booted');
        }
        final process = await _spawn('xcrun', [
          'simctl',
          'io',
          target.device,
          'recordVideo',
          '--codec=h264',
          stagingPath,
        ]);
        final handle = _ProcessRecording(process);
        try {
          await handle.waitForLine('Recording started', deadline);
          return handle;
        } catch (_) {
          await handle.stop().catchError((Object _) {});
          rethrow;
        }
      case RecordingPlatform.android:
        final devices = await _run('adb', ['devices'], deadline);
        if (!devices
            .split('\n')
            .any((line) => line.trim() == '${target.device}\tdevice')) {
          _unsupported('The selected Android device is not online/authorized');
        }
        // Only this generated name is interpolated into remote shell commands.
        final remote =
            '/sdcard/marionette-$pid-${DateTime.now().microsecondsSinceEpoch}.mp4';
        final process = await _spawn('adb', [
          '-s',
          target.device,
          'shell',
          'echo MRAPID:\$\$; exec screenrecord --verbose --time-limit 180 $remote',
        ]);
        final handle = _ProcessRecording(process);
        int? remotePid;
        handle.onLine = (line) {
          if (line.startsWith('MRAPID:')) {
            remotePid = int.tryParse(line.substring(7).trim());
          }
        };
        handle.beforeStop = () async {
          if (remotePid == null) return;
          // Check the unique recording path in cmdline before signaling. Never
          // kill all screenrecord processes or trust an old PID by itself.
          await _run('adb', [
            '-s',
            target.device,
            'shell',
            'case "\$(cat /proc/$remotePid/cmdline 2>/dev/null)" in '
                '*$remote*) kill -2 $remotePid;; esac',
          ], DateTime.now().add(const Duration(seconds: 5)));
        };
        handle.beforeAbort = () async {
          if (remotePid == null) return;
          await _run('adb', [
            '-s',
            target.device,
            'shell',
            'case "\$(cat /proc/$remotePid/cmdline 2>/dev/null)" in '
                '*$remote*) kill -9 $remotePid;; esac',
          ], DateTime.now().add(const Duration(seconds: 5)));
        };
        handle.afterStop = () async {
          await _run('adb', [
            '-s',
            target.device,
            'pull',
            remote,
            stagingPath,
          ], DateTime.now().add(const Duration(seconds: 20)));
          // Remove only our file, and only after successful retrieval.
          await _run('adb', [
            '-s',
            target.device,
            'shell',
            'rm',
            '-f',
            remote,
          ], DateTime.now().add(const Duration(seconds: 5)));
        };
        handle.signalLocal = false;
        try {
          while (true) {
            handle.checkAlive();
            _check(deadline);
            if (remotePid != null) {
              final length = await _run(
                'adb',
                ['-s', target.device, 'shell', 'stat', '-c', '%s', remote],
                deadline,
                allowFailure: true,
              );
              if ((int.tryParse(length.trim()) ?? 0) > 0) break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          return handle;
        } catch (_) {
          await handle.stop().catchError((Object _) {});
          rethrow;
        }
      case RecordingPlatform.macos:
        if (!Platform.isMacOS) {
          _unsupported('macOS display recording requires macOS');
        }
        final process = await _spawn('/usr/sbin/screencapture', [
          '-v',
          '-x',
          '-D',
          target.device,
          stagingPath,
        ]);
        final handle = _ProcessRecording(
          process,
          failureHint: 'Enable Screen Recording for the terminal/host app in macOS System Settings; check the display index.',
        );
        try {
          // screencapture can defer publishing its destination until stop.
          // It has no first-frame handshake: detect immediate permission/device
          // failures during startup, then validate the artifact on stop.
          final startup = DateTime.now().add(const Duration(seconds: 1));
          while (DateTime.now().isBefore(startup)) {
            handle.checkAlive();
            _check(deadline);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          handle.checkAlive();
          return handle;
        } catch (_) {
          await handle.stop().catchError((Object _) {});
          rethrow;
        }
    }
  }
}

Never _unsupported(String message) =>
    throw PlatformException('UNSUPPORTED_CAPABILITY', message);

void _check(DateTime deadline) {
  if (!deadline.isAfter(DateTime.now())) {
    throw const PlatformException(
      'TIMEOUT',
      'Recording request deadline exceeded',
    );
  }
}

Future<Process> _spawn(String executable, List<String> arguments) async {
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

Future<String> _run(
  String executable,
  List<String> args,
  DateTime deadline, {
  bool allowFailure = false,
}) async {
  _check(deadline);
  final process = await _spawn(executable, args);
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

class _ProcessRecording implements RecordingHandle {
  _ProcessRecording(this.process, {this.failureHint}) {
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
      _check(deadline);
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
