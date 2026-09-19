import 'dart:async';
import 'dart:io';

import '../platform_exception.dart';
import 'launch_options.dart';
import 'owned_process.dart';

export 'launch_options.dart';

abstract interface class ApplicationLauncher {
  Future<RunningApplication> start(LaunchOptions options, DateTime deadline);
  Future<void> dispose();
}

abstract interface class RunningApplication {
  Uri get uri;
  Map<String, Object?> get description;
  Future<int> get exited;
  Future<void> stop();
}

/// Environment-specific execution lives here; the agent only connects to [uri].
/// Does not install SDKs, rewrite app sources or use an already-running device.
class PlatformApplicationLauncher implements ApplicationLauncher {
  PlatformApplicationLauncher({
    String? emulator,
    String? adb,
    this.xcrun = 'xcrun',
  }) : emulator = emulator ?? _androidTool('emulator/emulator'),
       adb = adb ?? _androidTool('platform-tools/adb');
  final String emulator, adb, xcrun;
  final _active = <_Application>{};
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
    final app = _Application(options, root, xcrun);
    _active.add(app);
    app.onStopped = () => _active.remove(app);
    try {
      if (_disposed) {
        throw const PlatformException(
          'CONNECTION_LOST',
          'Application launcher is stopped',
        );
      }
      await app.lockProject();
      await app.command(
        '/bin/chmod',
        ['700', root.path],
        'Private application directory',
        deadline,
      );
      switch (options.platform) {
        case ApplicationPlatform.ios:
          await _ios(app, deadline);
        case ApplicationPlatform.android:
          await _android(app, deadline);
          await _flutter(app, 'emulator-${options.port}', deadline);
        case ApplicationPlatform.tester:
          await _flutter(app, 'flutter-tester', deadline);
        case ApplicationPlatform.macos:
          await _flutter(app, 'macos', deadline);
        case ApplicationPlatform.web:
          await _flutter(app, 'chrome', deadline);
      }
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

  Future<void> _flutter(
    _Application app,
    String device,
    DateTime deadline,
  ) async {
    final o = app.options;
    final uriFile = File('${app.root.path}/vm-uri');
    app.runner = await app.spawn(
      o.flutter,
      [
        'run',
        '-d',
        device,
        '--debug',
        '--no-pub',
        '--machine',
        '--target',
        o.target,
        '--vmservice-out-file=${uriFile.path}',
        if (o.platform == ApplicationPlatform.web) '--web-run-headless',
        if (o.platform == ApplicationPlatform.macos)
          '--dart-define=MARIONETTE_HEADLESS=true',
      ],
      'Flutter runner',
      deadline,
      environment: {
        if (o.platform == ApplicationPlatform.macos) 'MARIONETTE_HEADLESS': '1',
      },
    );
    await app.waitUntil(() async {
      // DWDS can publish its URI before Flutter has initialized the web app.
      // Match Flutter's debugger handshake: wait for this app's started event.
      if (o.platform == ApplicationPlatform.web && !app.runner!.appStarted) {
        return false;
      }
      if (!await uriFile.exists()) return false;
      final raw = await uriFile.readAsString();
      final uri = _localUri(raw.trim());
      if (uri == null) return false;
      app.serviceUri = uri;
      return true;
    }, deadline);
    await uriFile.delete();
  }

  Future<void> _android(_Application app, DateTime deadline) async {
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
  }

  Future<void> _ios(_Application app, DateTime deadline) async {
    final o = app.options;
    await app.command(
      o.flutter,
      [
        'build',
        'ios',
        '--simulator',
        '--debug',
        '--no-pub',
        '--target',
        o.target,
      ],
      'iOS build',
      deadline,
    );
    final output = Directory('${o.project}/build/ios/iphonesimulator');
    final apps = await output
        .list()
        .where((f) => f is Directory && f.path.endsWith('.app'))
        .toList();
    if (apps.length != 1) {
      throw const PlatformException(
        'IO_ERROR',
        'Expected one built iOS simulator app',
      );
    }
    final bundle = await app.command(
      '/usr/libexec/PlistBuddy',
      ['-c', 'Print :CFBundleIdentifier', '${apps.single.path}/Info.plist'],
      'iOS bundle identity',
      deadline,
    );
    await Directory(app.deviceSet).create();
    app.device = await app.simctl([
      'create',
      'Marionette-Headless',
      o.deviceType!,
      o.runtime!,
    ], deadline);
    if (!RegExp(r'^[A-Fa-f0-9-]{36}$').hasMatch(app.device!)) {
      app.device = null;
      throw const PlatformException('IO_ERROR', 'Invalid simulator identity');
    }
    await app.simctl(['boot', app.device!], deadline);
    // bootstatus may fail on initial migration although the simulator can boot.
    // The actual install, VM connection and first observation prove readiness.
    try {
      await app.simctl(['bootstatus', app.device!, '-b'], deadline);
    } on PlatformException {
      remaining(deadline);
    }
    await app.simctl(['install', app.device!, apps.single.path], deadline);
    app.runner = await app.spawn(
      xcrun,
      [
        'simctl',
        '--set',
        app.deviceSet,
        'launch',
        '--console',
        app.device!,
        bundle,
        '--enable-dart-profiling',
        '--enable-checked-mode',
        '--verify-entry-points',
      ],
      'iOS application',
      deadline,
    );
    await app.waitUntil(() async {
      var text = app.runner!.output;
      if (!text.contains('Dart VM service is listening on')) {
        text = await app.simctl([
          'spawn',
          app.device!,
          'log',
          'show',
          '--last',
          '1m',
          '--style',
          'compact',
          '--predicate',
          'eventMessage CONTAINS "Dart VM service is listening"',
        ], deadline);
      }
      final matches = RegExp(
        r'Dart VM service is listening on (https?://[^\s]+)',
      ).allMatches(text);
      if (matches.isEmpty) return false;
      app.serviceUri = _localUri(matches.last[1]!);
      return app.serviceUri != null;
    }, deadline);
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

Uri? _localUri(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !['http', 'ws'].contains(uri.scheme) ||
      !['127.0.0.1', 'localhost', '::1'].contains(uri.host) ||
      !uri.hasPort ||
      uri.port <= 0 ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

class _Application implements RunningApplication {
  _Application(this.options, this.root, this.xcrun);
  final LaunchOptions options;
  final Directory root;
  final String xcrun;
  final processes = <OwnedProcess>[];
  OwnedProcess? runner, emulator;
  String? device;
  Uri? serviceUri;
  Future<void>? _stopped;
  void Function()? onStopped;
  bool _cancelled = false;
  static final _projects = <String>{};
  String? _projectKey;
  RandomAccessFile? _projectLock;

  Future<void> lockProject() async {
    final key = await Directory(options.project).resolveSymbolicLinks();
    if (_cancelled) {
      throw const PlatformException(
        'CONNECTION_LOST',
        'Application launch cancelled',
      );
    }
    if (!_projects.add(key)) {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'This project already has a managed application',
      );
    }
    _projectKey = key;
    try {
      _projectLock = File('$key/.dart_tool/marionette-launch.lock')
          .openSync(mode: FileMode.append);
      _projectLock!.lockSync(FileLock.exclusive);
    } catch (_) {
      _projectLock?.closeSync();
      _projectLock = null;
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Project is in use or dependencies are not prepared',
        hint: 'Run flutter pub get, and close other managed runs of this project.',
      );
    }
  }

  String get deviceSet => '${root.path}/devices';
  @override
  Uri get uri => serviceUri!;
  @override
  Future<int> get exited => runner!.exited;
  @override
  Map<String, Object?> get description => {
    'platform': options.platform.name,
    'state': runner?.running == true ? 'running' : 'exited',
    'pid': runner?.process.pid,
    if (device != null) 'device': device,
  };

  Future<OwnedProcess> spawn(
    String executable,
    List<String> args,
    String label,
    DateTime deadline, {
    Map<String, String>? environment,
  }) async {
    if (_cancelled) {
      throw const PlatformException(
        'CONNECTION_LOST',
        'Application launch cancelled',
      );
    }
    final process = await OwnedProcess.start(
      executable,
      args,
      label: label,
      deadline: deadline,
      cwd: options.project,
      environment: environment,
    );
    if (_cancelled) {
      await process.stop();
      throw const PlatformException(
        'CONNECTION_LOST',
        'Application launch cancelled',
      );
    }
    processes.add(process);
    return process;
  }

  Future<String> command(
    String executable,
    List<String> args,
    String label,
    DateTime deadline,
  ) async {
    final p = await spawn(executable, args, label, deadline);
    return p.result(deadline);
  }

  Future<String> simctl(List<String> args, DateTime deadline) => command(
    xcrun,
    ['simctl', '--set', deviceSet, ...args],
    'iOS simulator',
    deadline,
  );

  Future<void> waitUntil(
    Future<bool> Function() ready,
    DateTime deadline,
  ) async {
    while (true) {
      if (_cancelled) {
        throw const PlatformException(
          'CONNECTION_LOST',
          'Application launch cancelled',
        );
      }
      remaining(deadline);
      if (runner?.running == false || emulator?.running == false) {
        throw const PlatformException(
          'CONNECTION_LOST',
          'Application or emulator exited before becoming ready',
        );
      }
      if (await ready()) {
        remaining(deadline);
        if (runner?.running == false || emulator?.running == false) continue;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Future<void> stop() => _stopped ??= _stop();
  Future<void> _stop() async {
    _cancelled = true;
    Object? failure;
    for (final p in processes.toList().reversed) {
      try {
        await p.stop();
      } catch (e) {
        failure ??= e;
      }
    }
    if (options.platform == ApplicationPlatform.ios && device != null) {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      Future<void> cleanup(String action) async {
        final p = await OwnedProcess.start(
          xcrun,
          ['simctl', '--set', deviceSet, action, device!],
          label: 'iOS cleanup',
          deadline: deadline,
        );
        await p.result(deadline);
      }

      try {
        await cleanup('shutdown');
      } catch (_) {}
      try {
        await cleanup('delete');
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure == null) {
      await root.delete(recursive: true);
      if (_projectLock != null) {
        _projectLock!.unlockSync();
        _projectLock!.closeSync();
        _projectLock = null;
      }
      if (_projectKey != null) _projects.remove(_projectKey);
      onStopped?.call();
    } else {
      throw const PlatformException(
        'IO_ERROR',
        'Could not confirm owned application cleanup',
        hint: 'Inspect the owned runner/device before relaunching.',
      );
    }
  }
}
