import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import 'capture_runner_assets.dart';

/// An independent XCTest runner observes the existing main screen. It never
/// launches/activates the app, interacts with UI, or uses simctl screenshot.
class IosScreenCapturer implements ScreenCapturer {
  IosScreenCapturer({
    this.xcrun = '/usr/bin/xcrun',
    bool? isMacOS,
    this.temporaryRoot,
  }) : _isMacOS = isMacOS ?? Platform.isMacOS;

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
  Future<DeviceScreenshot> capture(String device, DateTime deadline) {
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
