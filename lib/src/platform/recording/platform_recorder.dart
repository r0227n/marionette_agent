import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_web/marionette_agent_web.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Selects an implementation by target platform, independently of the host OS.
class PlatformScreenRecorder implements ScreenRecorder {
  const PlatformScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) {
    final ScreenRecorder recorder = switch (target.platform) {
      RecordingPlatform.ios => const IosScreenRecorder(),
      RecordingPlatform.android => const AndroidScreenRecorder(),
      RecordingPlatform.macos => const MacosScreenRecorder(),
      RecordingPlatform.web => const WebScreenRecorder(),
      _ => throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Screen recording is not implemented for this platform',
      ),
    };
    return recorder.start(target, stagingPath, deadline);
  }
}
