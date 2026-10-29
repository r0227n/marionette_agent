import 'dart:io';

import '../protocol/protocol.dart';

const screenshotSources = [
  'ios-simulator',
  'ios-device',
  'android-emulator',
  'macos',
];

/// Validate the one OS-screen acquisition route before any process is started.
void validateScreenshotRequest(Json params) {
  final source = params['source'] ?? 'ios-simulator';
  if (!screenshotSources.contains(source) ||
      (params.containsKey('source') && params['source'] is! String)) {
    invalid('Unknown screenshot source');
  }
  if (params.keys.any(
    (key) => !['source', 'device', 'path', 'display'].contains(key),
  )) {
    throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'OS screenshots do not support Flutter targets, crop or ref annotation',
    );
  }
  if (params.containsKey('path') &&
      (params['path'] is! String ||
          (params['path'] as String).isEmpty ||
          (params['path'] as String).contains('\u0000'))) {
    invalid('Invalid screenshot destination');
  }
  if (source == 'macos') {
    final display = params['display'];
    if (display is! int ||
        display < 1 ||
        display > 999 ||
        params.containsKey('device')) {
      invalid('macos source requires --display <1-999> and no device');
    }
    return;
  }
  if (params.containsKey('display')) {
    invalid('Display is only valid with source macos');
  }
  final device = params['device'];
  if (device is! String || device.isEmpty || device.contains('\u0000')) {
    invalid('Screenshot requires --device <UDID>');
  }
  if (source == 'ios-simulator' &&
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(device)) {
    invalid('Specify a Simulator UDID, never a name or booted');
  }
}

bool isNativeScreenshot(String command, Json params) => command == 'screenshot';

/// Resolve a pairing path before IPC; Simulator UDIDs are preserved verbatim.
String? resolveScreenshotDevice(Json params) => params['source'] == 'macos'
    ? null
    : params['source'] == 'android-emulator'
    ? File(params['device'] as String).absolute.path
    : params['device'] as String;
