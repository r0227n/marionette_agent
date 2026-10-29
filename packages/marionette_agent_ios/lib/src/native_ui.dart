import 'package:marionette_agent_platform_interface/host_support.dart';

/// Connects to the XCUITest runner; never spawns host input tools.
class IosNativeUi extends NativeRunnerUi {
  const IosNativeUi({super.configurationPath}) : super(platform: 'ios');
}
