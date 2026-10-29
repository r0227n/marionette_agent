import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/host_support.dart';

import 'package:marionette_agent_video/marionette_agent_video.dart';

import 'capture_runner_assets.dart';

/// An independent XCTest runner observes the existing main screen. It never
/// launches/activates the app, interacts with UI, or uses simctl screenshot.
class IosScreenCapturer implements ScreenCapturer {
  IosScreenCapturer({
    this.xcrun = '/usr/bin/xcrun',
    bool? isMacOS,
    this.temporaryRoot,
  }) : _isMacOS = isMacOS ?? Platform.isMacOS;

  static final _recordingFeeds =
      <
        String,
        ({String token, String runtime, Future<List<int>> Function() capture})
      >{};
  final String xcrun;
  final bool _isMacOS;
  final Directory? temporaryRoot;
  Directory? _build;
  String? _testRun;
  final _devices = <String>{};
  final _bundle =
      'dev.marionette.capture.r${List.generate(4, (_) => Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';
  Future<void> _queue = Future.value();
  bool _disposed = false;
  static final _udid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  // XCTest owns one host process at a time; serialize native observations even
  // across sessions. Expired queued work checks its deadline before any I/O.
  @override
  Future<DeviceScreenshot> capture(
    String device,
    DateTime deadline, {
    String? source,
  }) {
    final pending = _queue.then((_) async {
      try {
        return await _capture(device, deadline);
      } on PlatformException {
        rethrow;
      } catch (_) {
        throw const PlatformException(
          'IO_ERROR',
          'Cannot prepare or recover the XCUIScreen image',
        );
      }
    });
    _queue = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<DeviceScreenshot> _capture(String device, DateTime deadline) async {
    _check(deadline);
    if (_disposed) {
      throw const PlatformException('IO_ERROR', 'Screen capturer is closed');
    }
    if (!_udid.hasMatch(device)) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Specify a Simulator UDID, never a name or booted',
      );
    }
    if (!_isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'XCUIScreen capture requires macOS/Xcode',
      );
    }
    await _run(['--find', 'xcodebuild'], deadline, sdkProbe: true);
    // simctl is only an inventory/lifecycle service. Pixels come exclusively
    // from XCUIScreen.main.screenshot() in the bundled UI-test target.
    final inventory = await _run([
      'simctl',
      'list',
      'devices',
      'available',
      '--json',
    ], deadline);
    final matches = <({String device, String runtime, String state})>[];
    try {
      final devices =
          (jsonDecode(utf8.decode(inventory)) as Map)['devices'] as Map;
      for (final entry in devices.entries) {
        if (!(entry.key as String).startsWith(
          'com.apple.CoreSimulator.SimRuntime.iOS-',
        )) {
          continue;
        }
        for (final raw in entry.value as List) {
          final item = raw as Map;
          if ((item['udid'] as String).toUpperCase() == device.toUpperCase() &&
              item['isAvailable'] != false) {
            matches.add((
              device: item['udid'] as String,
              runtime: entry.key as String,
              state: item['state'] as String,
            ));
          }
        }
      }
    } catch (_) {
      throw const PlatformException('IO_ERROR', 'Invalid Simulator inventory');
    }
    if (matches.length > 1) {
      throw const PlatformException(
        'AMBIGUOUS_TARGET',
        'Simulator UDID is not unique',
      );
    }
    if (matches.isEmpty || matches.single.state != 'Booted') {
      throw const PlatformException(
        'UNRESOLVABLE_TARGET',
        'Selected iOS Simulator is unavailable or not booted',
      );
    }
    final selected = matches.single;
    final feed = _recordingFeeds[selected.device.toUpperCase()];
    if (feed != null) {
      final png = await feed.capture().timeout(
        deadline.difference(DateTime.now()),
      );
      return DeviceScreenshot(
        png: Uint8List.fromList(png),
        source: 'ios-simulator',
        device: selected.device,
        runtime: feed.runtime,
        display: 'main',
        mask: 'system-default',
        method: 'xcuiscreen',
      );
    }

    await _prepare(deadline);
    final work = await _build!.createTemp('capture-');
    try {
      _devices.add(selected.device);
      final result = '${work.path}/result.xcresult';
      await _run([
        'xcodebuild',
        'test-without-building',
        '-xctestrun',
        _testRun!,
        '-destination',
        'platform=iOS Simulator,id=${selected.device}',
        '-destination-timeout',
        '1',
        '-parallel-testing-enabled',
        'NO',
        '-only-testing:ScreenCapture/Capture/testCapture',
        '-resultBundlePath',
        result,
      ], deadline);
      final output = '${work.path}/attachments';
      await _run([
        'xcresulttool',
        'export',
        'attachments',
        '--path',
        result,
        '--output-path',
        output,
      ], deadline);
      _check(deadline);
      final records = jsonDecode(
        await File('$output/manifest.json').readAsString(),
      ) as List;
      final candidates = <String>[];
      for (final record in records) {
        if (record['testIdentifier'] != 'Capture/testCapture()') continue;
        for (final attachment in record['attachments'] as List) {
          if ((attachment['deviceId'] as String).toUpperCase() !=
                  selected.device.toUpperCase() ||
              attachment['isAssociatedWithFailure'] != false ||
              !(attachment['suggestedHumanReadableName'] as String).startsWith(
                'marionette-screen_',
              )) {
            continue;
          }
          final name = attachment['exportedFileName'] as String;
          if (!RegExp(r'^[A-Za-z0-9_-]+\.png$').hasMatch(name)) {
            throw const FormatException('Invalid attachment name');
          }
          candidates.add('$output/$name');
        }
      }
      if (candidates.length != 1) {
        throw const FormatException('Expected one main screen');
      }
      final path = candidates.single;
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Expected regular attachment');
      }
      final image = File(path);
      final size = await image.length();
      if (size == 0 || size > 32 * 1024 * 1024) {
        throw const FormatException('Invalid attachment size');
      }
      final png = await image.readAsBytes();
      _check(deadline);
      return DeviceScreenshot(
        png: png,
        source: 'ios-simulator',
        device: selected.device,
        runtime: selected.runtime,
        display: 'main',
        mask: 'system-default',
        method: 'xcuiscreen',
      );
    } on PlatformException {
      rethrow;
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot recover the XCUIScreen attachment',
      );
    } finally {
      await _terminate(selected.device);
      await work.delete(recursive: true).catchError((Object _) => work);
    }
  }

  /// One long-lived XCTest run supplies OS frames; no per-frame runner launch.
  Future<RecordingHandle> record(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) async {
    if (!_isMacOS || !_udid.hasMatch(target.device)) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Recording requires an iOS Simulator and Xcode',
      );
    }
    Process? runner;
    ServerSocket? reservation;
    String? planPath;
    final token = List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    Future<void> close() async {
      if (_recordingFeeds[target.device.toUpperCase()]?.token == token) {
        _recordingFeeds.remove(target.device.toUpperCase());
      }
      runner?.kill(ProcessSignal.sigint);
      if (runner != null) {
        try {
          await runner.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          runner.kill(ProcessSignal.sigkill);
        }
      }
      await _terminate(target.device);
      if (planPath != null) {
        await File(planPath).delete().catchError((Object _) => File(planPath!));
      }
      await dispose();
    }

    try {
      final inventory = jsonDecode(
        utf8.decode(
          await _run([
            'simctl',
            'list',
            'devices',
            'booted',
            '--json',
          ], deadline),
        ),
      ) as Map;
      final matches = <String>[];
      for (final entry in (inventory['devices'] as Map).entries) {
        if (!(entry.key as String).startsWith(
          'com.apple.CoreSimulator.SimRuntime.iOS-',
        )) {
          continue;
        }
        for (final item in entry.value as List) {
          if ((item['udid'] as String).toUpperCase() ==
                  target.device.toUpperCase() &&
              item['state'] == 'Booted' &&
              item['isAvailable'] != false) {
            matches.add(entry.key as String);
          }
        }
      }
      if (matches.length != 1) {
        throw PlatformException(
          matches.isEmpty ? 'UNRESOLVABLE_TARGET' : 'AMBIGUOUS_TARGET',
          'Select one available booted iOS Simulator',
        );
      }
      await _prepare(deadline);
      _devices.add(target.device);
      reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reservation.port;
      final plan = jsonDecode(
        await runRecordingCommand('/usr/bin/plutil', [
          '-convert',
          'json',
          '-o',
          '-',
          _testRun!,
        ], deadline),
      );
      void configure(dynamic node) {
        if (node is Map) {
          if (node.containsKey('TestBundlePath')) {
            (node['EnvironmentVariables'] ??= <String, dynamic>{}).addAll({
              'MRA_RECORD_PORT': '$port',
              'MRA_RECORD_TOKEN': token,
            });
          }
          for (final value in node.values) {
            configure(value);
          }
        } else if (node is List) {
          for (final value in node) {
            configure(value);
          }
        }
      }

      configure(plan);
      planPath = '${File(_testRun!).parent.path}/record.xctestrun';
      final jsonPath = '${_build!.path}/record.json';
      await File(jsonPath).writeAsString(jsonEncode(plan));
      await runRecordingCommand('/usr/bin/plutil', [
        '-convert',
        'xml1',
        '-o',
        planPath,
        jsonPath,
      ], deadline);
      await reservation.close();
      reservation = null;
      runner = await Process.start(xcrun, [
        'xcodebuild',
        'test-without-building',
        '-xctestrun',
        planPath,
        '-destination',
        'platform=iOS Simulator,id=${target.device}',
        '-parallel-testing-enabled',
        'NO',
        '-only-testing:ScreenCapture/Capture/testStream',
      ]);
      unawaited(runner.stdout.drain<void>());
      unawaited(runner.stderr.drain<void>());
      int? exit;
      unawaited(
        runner.exitCode.then((value) {
          exit = value;
        }),
      );
      var first = true;
      Future<List<int>> capture() async {
        final limit = first
            ? deadline
            : DateTime.now().add(const Duration(seconds: 5));
        Socket? socket;
        while (socket == null) {
          _check(limit);
          if (exit != null) {
            throw const PlatformException(
              'IO_ERROR',
              'XCTest recording runner exited',
            );
          }
          try {
            socket = await Socket.connect(
              InternetAddress.loopbackIPv4,
              port,
              timeout: const Duration(milliseconds: 200),
            );
          } on SocketException {
            if (!first) {
              throw const PlatformException(
                'CONNECTION_LOST',
                'XCTest recording disconnected',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        first = false;
        try {
          socket.write('$token\n');
          await socket.flush();
          final bytes = BytesBuilder();
          await socket
              .forEach((chunk) {
                if (bytes.length + chunk.length > 32 * 1024 * 1024) {
                  throw const PlatformException(
                    'IO_ERROR',
                    'XCTest frame too large',
                  );
                }
                bytes.add(chunk);
              })
              .timeout(limit.difference(DateTime.now()));
          return bytes.takeBytes();
        } finally {
          socket.destroy();
        }
      }

      final handle = await PngScreenRecorder(
        capture: capture,
        close: close,
      ).start(target, path, deadline);
      _recordingFeeds[target.device.toUpperCase()] = (
        token: token,
        runtime: matches.single,
        capture: capture,
      );
      return _RunnerRecording(handle, runner);
    } catch (_) {
      await reservation?.close();
      await close();
      rethrow;
    }
  }

  Future<void> _prepare(DateTime deadline) async {
    if (_testRun != null) return;
    final root = temporaryRoot ?? Directory.systemTemp;
    final directory = _build ??= await root.createTemp('mra-xcuiscreen-');
    try {
      for (final entry in captureRunnerFiles.entries) {
        final file = File('${directory.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      await _run([
        'xcodebuild',
        'build-for-testing',
        '-project',
        '${directory.path}/ScreenCapture.xcodeproj',
        '-scheme',
        'ScreenCapture',
        '-destination',
        'generic/platform=iOS Simulator',
        '-derivedDataPath',
        '${directory.path}/derived',
        'CODE_SIGNING_ALLOWED=NO',
        'PRODUCT_BUNDLE_IDENTIFIER=$_bundle',
      ], deadline);
      final products = Directory('${directory.path}/derived/Build/Products');
      final runs = await products
          .list()
          .where((e) => e is File && e.path.endsWith('.xctestrun'))
          .toList();
      if (runs.length != 1) {
        throw const PlatformException(
          'IO_ERROR',
          'XCTest runner build produced no unique test plan',
        );
      }
      _testRun = runs.single.path;
    } catch (_) {
      await directory
          .delete(recursive: true)
          .catchError((Object _) => directory);
      _build = null;
      rethrow;
    }
  }

  void _check(DateTime deadline) {
    if (!deadline.isAfter(DateTime.now())) {
      throw const PlatformException(
        'TIMEOUT',
        'XCUIScreen screenshot deadline exceeded',
        hint: 'The first screenshot builds and starts an XCTest runner; allow a longer --timeout.',
      );
    }
  }

  Future<Uint8List> _run(
    List<String> args,
    DateTime deadline, {
    bool sdkProbe = false,
  }) async {
    _check(deadline);
    Process? process;
    try {
      final starting = Process.start(xcrun, args);
      try {
        process = await starting.timeout(deadline.difference(DateTime.now()));
      } on TimeoutException {
        unawaited(
          starting.then<void>((p) {
            p.kill(ProcessSignal.sigkill);
          }, onError: (Object _) {}),
        );
        rethrow;
      }
      final child = process;
      final bytes = BytesBuilder(copy: false);
      final stdout = child.stdout.forEach((chunk) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024) {
          throw const PlatformException(
            'IO_ERROR',
            'XCTest output exceeds 32 MiB',
          );
        }
        bytes.add(chunk);
      });
      final results = await Future.wait<Object?>([
        child.exitCode,
        stdout,
        child.stderr.drain<void>(),
      ], eagerError: true).timeout(deadline.difference(DateTime.now()));
      _check(deadline);
      if (results.first != 0) {
        throw PlatformException(
          sdkProbe ? 'UNSUPPORTED_CAPABILITY' : 'IO_ERROR',
          sdkProbe
              ? 'Xcode XCTest tools are unavailable'
              : args.contains('build-for-testing')
              ? 'Cannot build XCUIScreen runner'
              : args.contains('test-without-building')
              ? 'XCUIScreen test execution failed'
              : args.contains('export')
              ? 'XCUIScreen attachment export failed'
              : 'Cannot query Simulator inventory',
        );
      }
      return bytes.takeBytes();
    } on PlatformException {
      rethrow;
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'XCUIScreen screenshot deadline exceeded',
        hint: 'Allow time for the XCTest runner build/start with --timeout.',
      );
    } on ProcessException {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Xcode XCTest tools are unavailable',
      );
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'XCUIScreen runner operation failed',
      );
    } finally {
      if (process != null) {
        process.kill(ProcessSignal.sigint);
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode
              .timeout(const Duration(seconds: 1))
              .catchError((Object _) => -1);
        }
      }
    }
  }

  Future<void> _lifecycle(List<String> args) async {
    try {
      await _run([
        'simctl',
        ...args,
      ], DateTime.now().add(const Duration(seconds: 3)));
    } catch (_) {}
  }

  Future<void> _terminate(String device) =>
      // The bundle ID is unique to this adapter; never terminate the observed app.
      _lifecycle(['terminate', device, '$_bundle.xctrunner']);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _queue;
    for (final device in _devices) {
      await _terminate(device);
      await _lifecycle(['uninstall', device, '$_bundle.xctrunner']);
    }
    if (_build != null) {
      await _build!.delete(recursive: true).catchError((Object _) => _build!);
    }
  }
}

/// Keep the device reserved until both acquisition and the owned test process end.
class _RunnerRecording implements RecordingHandle {
  _RunnerRecording(this.frames, Process runner) {
    final exited = runner.exitCode.then((_) {
      _running = false;
    });
    // A failed frame feed ends before its runner. Close it here so waiting for
    // process termination cannot deadlock automatic finalization in the manager.
    final finalized = frames.ended.then((_) async {
      try {
        await frames.stop();
      } catch (_) {
        // stop retains the original failure for the manager's later call.
      }
    });
    ended = Future.wait([finalized, exited]).then((_) {});
    unawaited(ended.catchError((Object _) {}));
  }
  final RecordingHandle frames;
  bool _running = true;
  @override
  late final Future<void> ended;
  @override
  bool get isRunning => _running || frames.isRunning;
  @override
  Future<void> stop() => frames.stop();
  @override
  Future<void> abort() => frames.abort();
}
