import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// The CLI composition root selects concrete implementations.
ScreenCapturer platformScreenCapturer() => IosScreenCapturer();
