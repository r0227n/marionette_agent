import 'launch_options.dart';

abstract interface class ApplicationLauncher {
  Future<RunningApplication> start(LaunchOptions options, DateTime deadline);
  Future<void> dispose();
}

abstract interface class RunningApplication {
  Uri get uri;
  Map<String, Object?> get description;
  Future<int> get exited;
  Future<void> stop();
}
