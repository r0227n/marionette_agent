import 'dart:typed_data';

/// Device pixels and their provenance. Image decoding and persistence belong to
/// the caller's common artifact writer, not the platform implementation.
class DeviceScreenshot {
  const DeviceScreenshot({
    required this.png,
    required this.source,
    required this.device,
    required this.runtime,
    required this.display,
    required this.mask,
  });

  final Uint8List png;
  final String source, device, runtime, display, mask;

  Map<String, Object?> get metadata => {
    'source': source,
    'device': device,
    'runtime': runtime,
    'display': display,
    'scope': 'device-screen',
    'mask': mask,
    'coordinateSpace': 'physical-pixels',
  };
}

abstract interface class ScreenCapturer {
  Future<DeviceScreenshot> capture(String device, DateTime deadline);
}
