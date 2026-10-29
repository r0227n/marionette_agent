import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import 'screen_capture.dart';

class IosScreenRecorder implements ScreenRecorder {
  const IosScreenRecorder();
  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) => IosScreenCapturer().record(target, path, deadline);
}
