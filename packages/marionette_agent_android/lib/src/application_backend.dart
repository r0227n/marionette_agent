import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

class AndroidApplicationBackend implements ApplicationBackend {
  AndroidApplicationBackend({String? emulator, String? adb})
    : emulator = emulator ?? _androidTool('emulator/emulator'),
      adb = adb ?? _androidTool('platform-tools/adb');
  final String emulator, adb;

  @override
  Future<void> start(ManagedApplication app, DateTime deadline) async {
    final o = app.options;
    // Check both emulator ports, then verify that the owned child stays alive
    // while observing the explicit serial. Stop uses its Process, never adb's
    // shared server or a serial that another process might have acquired.
    final sockets = <ServerSocket>[];
    try {
      for (final port in [o.port!, o.port! + 1]) {
        sockets.add(
          await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            port,
            shared: false,
          ),
        );
      }
    } on SocketException {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Android emulator port is already in use',
      );
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
    }
    final devices = await app.command(
      adb,
      ['devices'],
      'Android device discovery',
      deadline,
    );
    if (RegExp('^emulator-${o.port}\\s', multiLine: true).hasMatch(devices)) {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Android emulator serial is already in use',
      );
    }
    app.emulator = await app.spawn(
      emulator,
      [
        '-avd',
        o.avd!,
        '-port',
        '${o.port}',
        '-no-window',
        '-no-audio',
        '-no-snapshot',
        '-read-only',
      ],
      'Android emulator',
      deadline,
    );
    app.device = 'emulator-${o.port}';
    await app.waitUntil(() async {
      final list = await app.command(
        adb,
        ['devices'],
        'Android device discovery',
        deadline,
      );
      if (!RegExp(
        '^${app.device}\\s+device\\b',
        multiLine: true,
      ).hasMatch(list)) {
        return false;
      }
      try {
        return (await app.command(
              adb,
              ['-s', app.device!, 'shell', 'getprop', 'sys.boot_completed'],
              'Android boot readiness',
              deadline,
            )).trim() ==
            '1';
      } on PlatformException catch (error) {
        // adb can list a device before its shell is ready. Poll only this
        // read-only readiness check; never retry app/UI operations.
        if (error.code != 'IO_ERROR') rethrow;
        return false;
      }
    }, deadline);
    await startFlutterApplication(app, 'emulator-${o.port}', deadline);
  }
}

String _androidTool(String relative) {
  final env = Platform.environment;
  final sdk =
      env['ANDROID_HOME'] ??
      env['ANDROID_SDK_ROOT'] ??
      '${env['HOME']}/Library/Android/sdk';
  final candidate = '$sdk/$relative';
  return File(candidate).existsSync() ? candidate : relative.split('/').last;
}
