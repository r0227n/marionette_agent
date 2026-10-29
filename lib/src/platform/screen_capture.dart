import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Explicit screenshot source selection; acquisition failures never fall back.
ScreenCapturer platformScreenCapturer() => _ScreenCapturer();

class _ScreenCapturer implements ScreenCapturer {
  final _macos = MacosScreenshotService();
  final _ios = IosScreenCapturer();
  final _android = const AndroidScreenCapturer();

  @override
  Future<DeviceScreenshot> capture(
    String device,
    DateTime deadline, {
    String? source,
  }) => source == 'macos'
      ? _macos.capture(int.parse(device), deadline)
      : source == 'android-emulator'
      ? _android.capture(device, deadline)
      : _ios.capture(device, deadline);

  @override
  Future<void> dispose() async {
    await _macos.dispose();
    await _ios.dispose();
    await _android.dispose();
  }
}
