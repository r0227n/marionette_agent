import 'dart:async';
import 'dart:io';

import '../../marionette_agent_platform_interface.dart';
import 'owned_process.dart';

/// A target implementation prepares an owned environment using shared lifecycle
/// helpers. The facade owns project exclusion and startup/disposal coordination.
abstract interface class ApplicationBackend {
  Future<void> start(ManagedApplication app, DateTime deadline);
}

Future<void> startFlutterApplication(
  ManagedApplication app,
  String device,
  DateTime deadline, {
  bool waitForAppStarted = false,
  List<String> arguments = const [],
  Map<String, String> environment = const {},
}) async {
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
      ...arguments,
    ],
    'Flutter runner',
    deadline,
    environment: environment,
  );
  await app.waitUntil(() async {
    // DWDS can publish its URI before Flutter has initialized the web app.
    // Match Flutter's debugger handshake: wait for this app's started event.
    if (waitForAppStarted && !app.runner!.appStarted) {
      return false;
    }
    if (!await uriFile.exists()) return false;
    final raw = await uriFile.readAsString();
    final uri = localServiceUri(raw.trim());
    if (uri == null) return false;
    app.serviceUri = uri;
    return true;
  }, deadline);
  await uriFile.delete();
}

Uri? localServiceUri(String raw) {
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

class ManagedApplication implements RunningApplication {
  ManagedApplication(this.options, this.root);
  final LaunchOptions options;
  final Directory root;
  Future<void> Function()? cleanup;
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

  Future<void> prepare(DateTime deadline) async {
    await lockProject();
    await command(
      '/bin/chmod',
      ['700', root.path],
      'Private application directory',
      deadline,
    );
  }

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
    try {
      await cleanup?.call();
    } catch (error) {
      failure ??= error;
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
