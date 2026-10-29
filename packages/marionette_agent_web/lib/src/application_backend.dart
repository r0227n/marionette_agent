import 'package:marionette_agent_platform_interface/host_support.dart';

class WebApplicationBackend implements ApplicationBackend {
  const WebApplicationBackend();

  @override
  Future<void> start(ManagedApplication app, DateTime deadline) =>
      startFlutterApplication(
        app,
        'chrome',
        deadline,
        arguments: const ['--web-run-headless'],
        waitForAppStarted: true,
      );
}
