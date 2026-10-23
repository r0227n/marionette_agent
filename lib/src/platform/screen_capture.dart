import 'dart:convert';

import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import '../protocol/protocol.dart';

const defaultScreenCapturer = AndroidScreenCapturer();

/// Platform selection/error conversion; image decoding and saving stay shared.
Future<Json> captureAndroidScreen(
  String device,
  DateTime deadline, {
  ScreenCapturer capturer = const AndroidScreenCapturer(),
}) async {
  try {
    final screen = await capturer.capture(device, deadline);
    return {
      'images': [base64Encode(screen.png)],
      'capture': {
        'source': screen.source,
        'platform': 'android',
        'device': screen.device,
        'display': screen.display,
        'scope': 'entire-display',
        'coordinateSpace': 'physical-pixels',
        'protectedContent': 'not-detectable',
      },
    };
  } on PlatformException catch (error) {
    throw AgentError(error.code, error.message, hint: error.hint);
  }
}
