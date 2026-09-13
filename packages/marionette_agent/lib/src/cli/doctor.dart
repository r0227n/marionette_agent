import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../backend/doctor_probe.dart';
import '../protocol/protocol.dart';
import 'process_runner.dart';

typedef DiagnosticProcess = Future<ProcessResult> Function(
  String,
  List<String>,
  DateTime,
);

/// One-shot diagnostics. Never prepares runtime state or dispatches a request.
class Doctor {
  Doctor({
    String? os,
    String? dartVersion,
    String? runtimePath,
    this.packageRoot,
    this.namespace,
    DiagnosticProcess? process,
    Future<Json> Function(String, DateTime)? probe,
  }) : os = os ?? Platform.operatingSystem,
       dartVersion = dartVersion ?? Platform.version,
       runtimePath =
           runtimePath ?? Platform.environment['MARIONETTE_AGENT_RUNTIME_DIR'],
       process = process ?? runProcessUntil,
       probe = probe ?? probeVmService;

  final String os, dartVersion;
  final String? runtimePath, namespace;
  final Uri? packageRoot;
  final DiagnosticProcess process;
  final Future<Json> Function(String, DateTime) probe;

  Future<Json> run(
    DateTime deadline, {
    String? probeUri,
    bool quick = false,
    bool offline = false,
    bool fix = false,
  }) async {
    final checks = <Json>[];
    void add(
      String id,
      String status,
      String reason,
      String next, [
      Json details = const {},
    ]) {
      checks.add({
        'id': id,
        'status': status,
        'reason': reason,
        'nextStep': next,
        'details': details,
      });
    }

    Future<void> check(String id, Future<void> Function() body) async {
      if ((quick &&
              {
                'dependencies.fixed',
                'simulators.ios',
                'probe.vmService',
              }.contains(id)) ||
          (offline && id == 'probe.vmService')) {
        add(
          id,
          'skipped',
          'Skipped by the selected diagnostic mode.',
          'Run doctor without --quick/--offline for this check.',
        );
        return;
      }
      if (!deadline.isAfter(DateTime.now())) {
        add(
          id,
          'unknown',
          'Overall deadline exhausted; check not performed.',
          'Retry doctor with a larger --timeout.',
        );
        return;
      }
      try {
        await body();
      } on TimeoutException {
        add(
          id,
          'unknown',
          'Check timed out.',
          'Retry doctor with a larger --timeout.',
        );
      } catch (_) {
        add(
          id,
          'unknown',
          'Check could not be completed.',
          'Check host tools and access permissions, then retry doctor.',
        );
      }
    }

    add(
      'host.os',
      os == 'macos' ? 'success' : 'failure',
      'Host OS: $os.',
      'Use macOS with Xcode for iOS Simulator support.',
    );
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(dartVersion);
    final supported =
        match != null &&
        int.parse(match[1]!) == 3 &&
        (int.parse(match[2]!) > 13 ||
            (int.parse(match[2]!) == 13 && int.parse(match[3]!) >= 2));
    add(
      'host.dart',
      supported ? 'success' : 'failure',
      'Required Dart range: >=3.13.2 <4.0.0.',
      'Use a Flutter/Dart SDK satisfying ^3.13.2.',
      {'version': match?.group(0)},
    );
    String? directory;
    bool safe = false;
    await check('runtime.directory', () async {
      final id = await process('/usr/bin/id', ['-u'], deadline);
      final uid = '${id.stdout}'.trim();
      if (id.exitCode != 0 || !RegExp(r'^\d+$').hasMatch(uid)) {
        throw const FormatException();
      }
      directory = runtimePath ?? '/tmp/mra-$uid';
      if (namespace != null) directory = '$directory-$namespace';
      final valid =
          p.isAbsolute(directory!) && utf8.encode(directory!).length <= 80;
      add(
        'runtime.socketPath',
        valid ? 'success' : 'failure',
        'Runtime must be absolute and at most 80 UTF-8 bytes (socket suffix /s).',
        'Set MARIONETTE_AGENT_RUNTIME_DIR to a short private absolute path.',
        {
          'directoryBytes': utf8.encode(directory!).length,
          'socketBytes': utf8.encode(p.join(directory!, 's')).length,
        },
      );
      if (!valid) {
        add(
          'runtime.directory',
          'skipped',
          'Invalid runtime path.',
          'Correct MARIONETTE_AGENT_RUNTIME_DIR.',
        );
        return;
      }
      final type = FileSystemEntity.typeSync(directory!, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        add(
          'runtime.directory',
          'skipped',
          'Runtime directory is absent; nothing was created.',
          'Run connect when ready to create runtime state.',
        );
        return;
      }
      if (type != FileSystemEntityType.directory) {
        add(
          'runtime.directory',
          'failure',
          'Runtime path is not a real directory.',
          'Select a private directory owned by the current user.',
        );
        return;
      }
      var stat = await process(
        '/usr/bin/stat',
        os == 'macos'
            ? ['-f', '%u:%Lp', directory!]
            : ['-c', '%u:%a', directory!],
        deadline,
      );
      if (fix &&
          stat.exitCode == 0 &&
          '${stat.stdout}'.trim().startsWith('$uid:') &&
          '${stat.stdout}'.trim() != '$uid:700') {
        final repaired = await process('/bin/chmod', [
          '700',
          directory!,
        ], deadline);
        if (repaired.exitCode == 0) {
          stat = await process(
            '/usr/bin/stat',
            os == 'macos'
                ? ['-f', '%u:%Lp', directory!]
                : ['-c', '%u:%a', directory!],
            deadline,
          );
          add(
            'runtime.repair',
            'success',
            'Restored owned runtime directory permissions to 0700.',
            'No daemon or application was restarted.',
          );
        }
      }
      safe = stat.exitCode == 0 && '${stat.stdout}'.trim() == '$uid:700';
      add(
        'runtime.directory',
        safe ? 'success' : 'failure',
        safe
            ? 'Owner matches current user; mode is 0700.'
            : 'Could not verify current-user ownership and mode 0700.',
        'Inspect directory owner and permissions; use a private directory.',
      );
    });
    if (!checks.any((check) => check['id'] == 'runtime.socketPath')) {
      add(
        'runtime.socketPath',
        'unknown',
        'Runtime location could not be determined.',
        'Check current-user identity and retry doctor.',
      );
    }
    await check('daemon.ipc', () async {
      if (!safe ||
          directory == null ||
          FileSystemEntity.typeSync(
                p.join(directory!, 's'),
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
        add(
          'daemon.ipc',
          'skipped',
          'No safely inspectable daemon socket.',
          'Run connect when ready; doctor never starts a daemon.',
        );
        return;
      }
      final localDeadline = DateTime.now().add(const Duration(seconds: 1));
      final end = localDeadline.isBefore(deadline) ? localDeadline : deadline;
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress(
            p.join(directory!, 's'),
            type: InternetAddressType.unix,
          ),
          0,
          timeout: remaining(end),
        );
        final hello = await decodeFrames(socket).first.timeout(remaining(end));
        final healthy =
            hello['protocolVersion'] == protocolVersion &&
            hello['ready'] == true;
        add(
          'daemon.ipc',
          healthy ? 'success' : 'failure',
          healthy
              ? 'Daemon handshake is ready and compatible.'
              : 'Daemon handshake is incompatible or not ready.',
          'Check CLI/daemon versions; close sessions before manually restarting the daemon.',
          {
            'expectedProtocol': protocolVersion,
            'protocolMatches': hello['protocolVersion'] == protocolVersion,
            'ready': hello['ready'] == true,
          },
        );
      } on SocketException {
        add(
          'daemon.ipc',
          'failure',
          'Daemon socket did not accept a connection.',
          'Inspect daemon state; doctor does not delete stale sockets.',
        );
      } finally {
        socket?.destroy();
      }
    });
    await check('dependencies.fixed', () async {
      final root =
          packageRoot ?? (await _packageRoot().timeout(remaining(deadline)));
      final spec = loadYaml(
        await _readMetadata(root.resolve('pubspec.yaml'), deadline),
      );
      final lock = loadYaml(
        await _readMetadata(root.resolve('pubspec.lock'), deadline),
      );
      final pins = <String, Object?>{};
      var matches = true;
      for (final name in ['marionette_mcp', 'image', 'yaml']) {
        final declared = spec['dependencies'][name];
        final resolved = lock['packages'][name]['version'];
        matches =
            matches &&
            declared is String &&
            resolved is String &&
            declared == resolved;
        pins[name] = {'declared': declared, 'locked': resolved};
      }
      add(
        'dependencies.fixed',
        matches ? 'success' : 'failure',
        'Package declarations compared with lockfile; these are not observed binding versions.',
        'Run dart pub get in the CLI package and check fixed dependency declarations.',
        pins,
      );
    });
    await check('simulators.ios', () async {
      if (os != 'macos') {
        add(
          'simulators.ios',
          'skipped',
          'iOS Simulator inspection requires macOS.',
          'Use macOS with Xcode.',
        );
        return;
      }
      final result = await process('/usr/bin/xcrun', [
        'simctl',
        'list',
        'devices',
        'available',
        '--json',
      ], deadline);
      if (result.exitCode != 0) throw const FormatException();
      final raw = jsonDecode('${result.stdout}') as Map;
      final devices = <Json>[];
      for (final entry in (raw['devices'] as Map).entries) {
        if (!(entry.key as String).contains('.iOS-')) continue;
        for (final device in entry.value as List) {
          if (device['isAvailable'] == true) {
            devices.add({
              'udid': device['udid'],
              'name': device['name'],
              'state': device['state'],
              'runtime': entry.key,
            });
          }
        }
      }
      add(
        'simulators.ios',
        devices.isEmpty ? 'failure' : 'success',
        '${devices.length} available iOS Simulators.',
        'Install an iOS Simulator runtime/device in Xcode if needed.',
        {'devices': devices},
      );
    });
    if (probeUri == null) {
      add(
        'probe.vmService',
        'skipped',
        'No explicit --probe-uri; no VM Service connection attempted.',
        'Pass --probe-uri explicitly to inspect a running app.',
      );
    } else {
      await check('probe.vmService', () async {
        try {
          final observed = await probe(probeUri, deadline);
          add(
            'probe.vmService',
            'success',
            'VM Service responded; binding fields contain only observations.',
            'Check observed extensions and binding version before using app operations.',
            observed,
          );
        } on TimeoutException {
          rethrow;
        } catch (_) {
          add(
            'probe.vmService',
            'failure',
            'VM Service probe failed (URI and remote errors withheld).',
            'Check the app is running and supply its current VM Service URI.',
          );
        }
      });
    }
    return {
      'doctor': true,
      'exitCode':
          checks.any(
            (c) => c['status'] == 'failure' || c['status'] == 'unknown',
          )
          ? 1
          : 0,
      'checks': checks,
    };
  }
}

Future<String> _readMetadata(Uri uri, DateTime deadline) async {
  final file = File.fromUri(uri);
  final stat = await file.stat().timeout(remaining(deadline));
  if (stat.type != FileSystemEntityType.file || stat.size > 1024 * 1024) {
    throw const FormatException('Expected bounded regular package metadata');
  }
  return file.readAsString().timeout(remaining(deadline));
}

Future<Uri> _packageRoot() async {
  final uri = (await Isolate.resolvePackageUri(
    Uri.parse('package:marionette_agent/src/cli/doctor.dart'),
  ))!;
  return uri.resolve('../../../');
}
