import 'dart:convert';

import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import '../protocol/protocol.dart';

typedef NativeScreenshotCapture = Future<Json> Function(
  int display,
  DateTime deadline,
);

Future<Json> captureMacosScreenshot(int display, DateTime deadline) async {
  try {
    final shot = await const MacosScreenshotService().capture(
      display,
      deadline,
    );
    return {
      'images': [base64Encode(shot.png)],
      'capture': shot.metadata,
    };
  } on PlatformException catch (error) {
    throw AgentError(error.code, error.message, hint: error.hint);
  }
}
