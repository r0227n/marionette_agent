import 'package:marionette_agent_platform_interface/host_support.dart';

class MacosApplicationBackend implements ApplicationBackend {
  const MacosApplicationBackend();

  @override
  Future<void> start(ManagedApplication app, DateTime deadline) =>
      startFlutterApplication(
        app,
        'macos',
        deadline,
        arguments: const ['--dart-define=MARIONETTE_HEADLESS=true'],
        environment: const {'MARIONETTE_HEADLESS': '1'},
      );
}
