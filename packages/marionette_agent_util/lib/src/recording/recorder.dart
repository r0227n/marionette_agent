import 'web_target.dart';

/// Recording targets, independent of the host OS.
enum RecordingPlatform { ios, android, macos, web, linux, windows }

class RecordingTarget {
  const RecordingTarget(this.platform, this.device, {this.fps});
  final int? fps;
  final RecordingPlatform platform;

  /// Simulator UDID, adb serial, display index, or explicit Web display/page pair.
  final String device;
  String get key {
    if (platform == RecordingPlatform.web) {
      final web = WebRecordingTarget.parse(device);
      if (web != null) return 'macos:${web.display}';
    }
    return '${platform.name}:$device';
  }

  String get extension =>
      platform == RecordingPlatform.macos || platform == RecordingPlatform.web
      ? '.mov'
      : '.mp4';
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
