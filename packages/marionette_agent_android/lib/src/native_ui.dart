import 'package:marionette_agent_platform_interface/host_support.dart';

/// Connects to the UI Automator runner; never spawns host input tools.
class AndroidNativeUi extends NativeRunnerUi {
  const AndroidNativeUi({super.configurationPath}) : super(platform: 'android');
}
