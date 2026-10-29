import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

Future<List<Map<String, Object?>>> listIosDevices(DateTime deadline) async {
  if (!Platform.isMacOS) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'iOS Simulator inventory requires macOS',
    );
  }
  try {
    final devices =
        (jsonDecode(
              await readDeviceInventory('xcrun', [
                'simctl',
                'list',
                'devices',
                'available',
                '--json',
              ], deadline),
            ) as Map)['devices']
            as Map;
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
  } catch (_) {
    throw const PlatformException('IO_ERROR', 'Cannot enumerate devices');
  }
}
