import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:marionette_agent_video/marionette_agent_video.dart';

import 'screen_capture.dart';

/// Captures display 0 through the paired UI Automator instrumentation API.
/// The instrumentation belongs to the caller; stop releases only this recording.
class AndroidScreenRecorder implements ScreenRecorder {
  const AndroidScreenRecorder();

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) {
    const source = AndroidScreenCapturer();
    return PngScreenRecorder(
      capture: () async => (await source.capture(
        target.device,
        DateTime.now().add(const Duration(seconds: 5)),
      )).png,
      close: source.dispose,
    ).start(target, stagingPath, deadline);
  }
}
