import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

class MacosScreenRecorder implements ScreenRecorder {
  const MacosScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    if (!Platform.isMacOS) {
      unsupported('macOS display recording requires macOS');
    }
    final process = await spawnRecordingProcess('/usr/sbin/screencapture', [
      '-v',
      '-x',
      '-D',
      target.device,
      stagingPath,
    ]);
    final handle = ProcessRecording(
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
        checkRecordingDeadline(deadline);
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

Never unsupported(String message) =>
    throw PlatformException('UNSUPPORTED_CAPABILITY', message);
