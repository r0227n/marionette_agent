import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

const screenshotDevice = '11111111-2222-3333-4444-555555555555';

class FakeScreenCapturer implements ScreenCapturer {
  FakeScreenCapturer(List<int> bytes) : png = Uint8List.fromList(bytes);
  final Uint8List png;
  final devices = <String>[];
  PlatformException? failure;

  @override
  Future<void> dispose() async {}

  @override
  Future<DeviceScreenshot> capture(String device, DateTime deadline) async {
    devices.add(device);
    if (failure != null) throw failure!;
    return DeviceScreenshot(
      png: png,
      source: 'ios-simulator',
      device: device,
      runtime: 'com.apple.CoreSimulator.SimRuntime.iOS-26-2',
      display: 'main',
      mask: 'system-default',
    );
  }
}
