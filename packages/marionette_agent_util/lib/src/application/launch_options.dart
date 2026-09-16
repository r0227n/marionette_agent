import 'dart:io';

import '../platform_exception.dart';

enum ApplicationPlatform { tester, ios, android, macos, web }

/// Closed launch contract shared by CLI and daemon. No shell command strings.
class LaunchOptions {
  LaunchOptions.fromJson(Map<String, Object?> json) {
    const fields = {
      'project',
      'platform',
      'flutter',
      'target',
      'deviceType',
      'runtime',
      'avd',
      'port',
    };
    if (json.keys.any((key) => !fields.contains(key))) _invalid();
    String? value(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is! String || v.trim().isEmpty || v.contains('\u0000')) _invalid();
      return v;
    }

    final selected = value('platform');
    platform =
        ApplicationPlatform.values
            .where((p) => p.name == selected)
            .firstOrNull ??
        _invalid();
    project = value('project') ?? _invalid();
    if (!File(project).isAbsolute) _invalid();
    flutter = value('flutter') ?? 'flutter';
    target = value('target') ?? 'lib/main.dart';
    if (flutter.startsWith('-') || target.startsWith('-')) _invalid();
    deviceType = value('deviceType');
    runtime = value('runtime');
    avd = value('avd');
    final rawPort = json['port'];
    if (rawPort != null &&
        (rawPort is! int ||
            rawPort < 5554 ||
            rawPort > 5682 ||
            rawPort.isOdd)) {
      _invalid();
    }
    port = rawPort as int?;
    if (platform == ApplicationPlatform.ios) {
      if (deviceType == null ||
          runtime == null ||
          !deviceType!.startsWith('com.apple.CoreSimulator.SimDeviceType.') ||
          !runtime!.startsWith('com.apple.CoreSimulator.SimRuntime.iOS-')) {
        _invalid();
      }
    } else if (deviceType != null || runtime != null) {
      _invalid();
    }
    if (platform == ApplicationPlatform.android) {
      if (avd == null ||
          !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(avd!) ||
          avd!.startsWith('-') ||
          port == null) {
        _invalid();
      }
    } else if (avd != null || port != null) {
      _invalid();
    }
  }

  late final ApplicationPlatform platform;
  late final String project, flutter, target;
  late final String? deviceType, runtime, avd;
  late final int? port;
}

Never _invalid() => throw const PlatformException(
  'INVALID_ARGUMENT',
  'Invalid launch options',
  hint: 'Choose a platform and project; iOS requires --device-type and --runtime, Android requires --avd and an unused even --port (5554..5682).',
);
