import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_web/marionette_agent_web.dart';
import 'package:marionette_agent_flutter/marionette_agent_flutter.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';

/// Coordinates shared lifecycle and selects the target implementation.
/// Does not install SDKs, rewrite app sources or use an already-running device.
class PlatformApplicationLauncher implements ApplicationLauncher {
  PlatformApplicationLauncher({
    String? emulator,
    String? adb,
    String xcrun = 'xcrun',
  }) : _backends = {
         ApplicationPlatform.ios: IosApplicationBackend(xcrun: xcrun),
         ApplicationPlatform.android: AndroidApplicationBackend(
           emulator: emulator,
           adb: adb,
         ),
         ApplicationPlatform.macos: const MacosApplicationBackend(),
         ApplicationPlatform.web: const WebApplicationBackend(),
         ApplicationPlatform.tester: const FlutterApplicationBackend(),
       };
  final Map<ApplicationPlatform, ApplicationBackend> _backends;
  final _active = <ManagedApplication>{};
  bool _disposed = false;

  @override
  Future<void> dispose() async {
    _disposed = true;
    await Future.wait(_active.toList().map((app) => app.stop()));
  }

  @override
  Future<RunningApplication> start(
    LaunchOptions options,
    DateTime deadline,
  ) async {
    if (!Platform.isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Application launch currently requires a macOS host',
      );
    }
    remaining(deadline);
    if (_disposed) {
      throw const PlatformException(
        'CONNECTION_LOST',
        'Application launcher is stopped',
      );
    }
    if (!await File('${options.project}/pubspec.yaml').exists() ||
        !await File(
          File(options.target).isAbsolute
              ? options.target
              : '${options.project}/${options.target}',
        ).exists()) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Flutter project or entrypoint is missing',
      );
    }
    final root = await Directory.systemTemp.createTemp('mra-app-');
    final app = ManagedApplication(options, root);
    _active.add(app);
    app.onStopped = () => _active.remove(app);
    try {
      if (_disposed) {
        throw const PlatformException(
          'CONNECTION_LOST',
          'Application launcher is stopped',
        );
      }
      await app.prepare(deadline);
      await _backends[options.platform]!.start(app, deadline);
      remaining(deadline);
      return app;
    } on TimeoutException {
      await app.stop();
      throw const PlatformException(
        'TIMEOUT',
        'Application launch deadline exceeded',
        hint: 'Use a longer --timeout for builds and the first device boot.',
      );
    } on PlatformException {
      await app.stop();
      rethrow;
    } catch (_) {
      await app.stop();
      throw const PlatformException('IO_ERROR', 'Application launch failed');
    }
  }
}
