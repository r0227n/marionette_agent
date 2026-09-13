import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'platform_exception.dart';

/// Read-only inventory of available iOS Simulators or online Android targets.
Future<List<Map<String, Object?>>> listDevices(
  String platform,
  DateTime deadline,
) async {
  if (!['ios', 'android'].contains(platform)) {
    throw const PlatformException(
      'INVALID_ARGUMENT',
      'Expected ios or android',
    );
  }
  if (platform == 'ios' && !Platform.isMacOS) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'iOS Simulator inventory requires macOS',
    );
  }
  Process? process;
  try {
    final duration = deadline.difference(DateTime.now());
    if (duration <= Duration.zero) throw TimeoutException('device list');
    final pending = Process.start(
      platform == 'ios' ? 'xcrun' : 'adb',
      platform == 'ios'
          ? ['simctl', 'list', 'devices', 'available', '--json']
          : ['devices', '-l'],
    );
    try {
      process = await pending.timeout(duration);
    } on TimeoutException {
      unawaited(
        pending.then((value) {
          value.kill(ProcessSignal.sigkill);
        }),
      );
      rethrow;
    }
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    final code = await process.exitCode.timeout(
      deadline.difference(DateTime.now()),
    );
    final text = await output.timeout(deadline.difference(DateTime.now()));
    await errors.timeout(deadline.difference(DateTime.now()));
    if (code != 0) {
      throw const PlatformException('IO_ERROR', 'Cannot enumerate devices');
    }
    if (platform == 'android') {
      return [
        for (final line in text.split('\n').skip(1))
          if (RegExp(r'^\S+\s+device(?:\s|$)').hasMatch(line))
            {
              'platform': 'android',
              'id': line.split(RegExp(r'\s+')).first,
              'state': 'device',
            },
      ];
    }
    final devices = (jsonDecode(text) as Map)['devices'] as Map;
    return [
      for (final entry in devices.entries)
        if ((entry.key as String).contains('.iOS-'))
          for (final device in entry.value as List)
            {
              'platform': 'ios',
              'id': device['udid'],
              'name': device['name'],
              'state': device['state'],
              'runtime': entry.key,
            },
    ];
  } on PlatformException {
    rethrow;
  } on TimeoutException {
    throw const PlatformException(
      'TIMEOUT',
      'Device inventory deadline exceeded',
    );
  } catch (_) {
    throw const PlatformException('IO_ERROR', 'Cannot enumerate devices');
  } finally {
    process?.kill(ProcessSignal.sigkill);
  }
}
