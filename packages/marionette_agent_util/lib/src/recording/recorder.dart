/// Recording targets, independent of the host OS.
enum RecordingPlatform { ios, android, macos, web, linux, windows }

class RecordingTarget {
  const RecordingTarget(this.platform, this.device);
  final RecordingPlatform platform;

  /// Simulator UDID, adb serial, or one-based macOS display index.
  final String device;
  String get key => '${platform.name}:$device';
}

/// Backends write into a private staging directory owned by the manager.
/// start completes after backend-specific startup confirmation. stop must finalize the file.
abstract interface class ScreenRecorder {
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  );
}

abstract interface class RecordingHandle {
  /// Completes when capture ends (including automatic limits or failure).
  Future<void> get ended;

  /// Remains true until capture process termination has been observed.
  bool get isRunning;

  /// Idempotent. Throws if capture or finalization failed.
  Future<void> stop();

  /// Force termination of this capture only; do not publish an incomplete file.
  /// Must be safe after stop and must not wait indefinitely for process exit.
  Future<void> abort();
}
