import 'package:marionette_agent_platform_interface/host_support.dart';

class FlutterApplicationBackend implements ApplicationBackend {
  const FlutterApplicationBackend();

  @override
  Future<void> start(ManagedApplication app, DateTime deadline) =>
      startFlutterApplication(app, 'flutter-tester', deadline);
}
