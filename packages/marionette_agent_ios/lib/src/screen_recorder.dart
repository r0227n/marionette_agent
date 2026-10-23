import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:marionette_agent_platform_interface/host_support.dart';

class IosScreenRecorder implements ScreenRecorder {
  const IosScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    if (!Platform.isMacOS) {
      unsupported('iOS Simulator requires macOS/Xcode');
    }
    final devices = jsonDecode(
      await runRecordingCommand('xcrun', [
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
      unsupported('The selected iOS Simulator is not booted');
    }
    final process = await spawnRecordingProcess('xcrun', [
      'simctl',
      'io',
      target.device,
      'recordVideo',
      '--codec=h264',
      stagingPath,
    ]);
    final handle = ProcessRecording(process);
    try {
      await handle.waitForLine('Recording started', deadline);
      return handle;
    } catch (_) {
      await handle.stop().catchError((Object _) {});
      rethrow;
    }
  }
}

Never unsupported(String message) =>
    throw PlatformException('UNSUPPORTED_CAPABILITY', message);
