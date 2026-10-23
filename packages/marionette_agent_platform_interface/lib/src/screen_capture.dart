import 'dart:typed_data';

/// Native screen pixels, with no relationship to Flutter logical coordinates.
class CapturedScreen {
  const CapturedScreen(
    this.png, {
    required this.source,
    required this.device,
    required this.display,
  });
  final Uint8List png;
  final String source, device;
  final int display;
}

abstract interface class ScreenCapturer {
  Future<CapturedScreen> capture(String device, DateTime deadline);
}
