import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

class AndroidScreenRecorder implements ScreenRecorder {
  const AndroidScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    final devices = await runRecordingCommand('adb', ['devices'], deadline);
    if (!devices
        .split('\n')
        .any((line) => line.trim() == '${target.device}\tdevice')) {
      unsupported('The selected Android device is not online/authorized');
    }
    // Only this generated name is interpolated into remote shell commands.
    final remote =
        '/sdcard/marionette-$pid-${DateTime.now().microsecondsSinceEpoch}.mp4';
    final process = await spawnRecordingProcess('adb', [
      '-s',
      target.device,
      'shell',
      'echo MRAPID:\$\$; exec screenrecord --verbose --time-limit 180 $remote',
    ]);
    final handle = ProcessRecording(process);
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
      await runRecordingCommand('adb', [
        '-s',
        target.device,
        'shell',
        'case "\$(cat /proc/$remotePid/cmdline 2>/dev/null)" in '
            '*$remote*) kill -2 $remotePid;; esac',
      ], DateTime.now().add(const Duration(seconds: 5)));
    };
    handle.beforeAbort = () async {
      if (remotePid == null) return;
      await runRecordingCommand('adb', [
        '-s',
        target.device,
        'shell',
        'case "\$(cat /proc/$remotePid/cmdline 2>/dev/null)" in '
            '*$remote*) kill -9 $remotePid;; esac',
      ], DateTime.now().add(const Duration(seconds: 5)));
    };
    handle.afterStop = () async {
      await runRecordingCommand('adb', [
        '-s',
        target.device,
        'pull',
        remote,
        stagingPath,
      ], DateTime.now().add(const Duration(seconds: 20)));
      // Remove only our file, and only after successful retrieval.
      await runRecordingCommand('adb', [
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
        checkRecordingDeadline(deadline);
        if (remotePid != null) {
          final length = await runRecordingCommand(
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
  }
}

Never unsupported(String message) =>
    throw PlatformException('UNSUPPORTED_CAPABILITY', message);
