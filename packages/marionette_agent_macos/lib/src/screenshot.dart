import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/host_support.dart';

import 'capture_runner_assets.dart';
import 'displays.dart';

/// OS pixels from an independent, locally signed macOS XCTest runner.
class MacosScreenshot extends DeviceScreenshot {
  MacosScreenshot(Uint8List png, this.captureMetadata)
    : super(
        png: png,
        source: 'macos-xcuiscreen',
        device: 'local',
        runtime: 'macos',
        display: '${captureMetadata['displayIndex']}',
        mask: 'system-default',
      );
  final Map<String, Object?> captureMetadata;
  @override
  Map<String, Object?> get metadata => captureMetadata;
}

class MacosScreenshotService {
  MacosScreenshotService({
    this.xcrun = '/usr/bin/xcrun',
    this.temporaryRoot,
    this.permission = screenCaptureAllowed,
    this.displays = activeMacosDisplays,
  });
  final String xcrun;
  final Directory? temporaryRoot;
  final bool Function() permission;
  final List<MacosDisplay> Function() displays;
  Directory? _build;
  String? _testRun;
  final _bundle =
      'dev.marionette.macos.capture.r${List.generate(4, (_) => Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';
  Future<void> _queue = Future.value();
  bool _disposed = false;

  Future<MacosScreenshot> capture(int display, DateTime deadline) {
    final pending = _queue.then((_) async {
      try {
        return await _capture(display, deadline);
      } on PlatformException {
        rethrow;
      } catch (_) {
        throw const PlatformException(
          'IO_ERROR',
          'Cannot recover macOS XCTest screenshot',
        );
      }
    });
    _queue = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  void _permission() {
    if (!permission()) {
      throw const PlatformException(
        'SCREEN_CAPTURE_PERMISSION_REQUIRED',
        'Screen Recording permission is not granted (denied or not requested)',
        hint: 'Enable Screen Recording for the terminal/host app, then explicitly retry. No permission prompt is requested.',
      );
    }
  }

  void _check(DateTime deadline) {
    if (!deadline.isAfter(DateTime.now())) {
      throw const PlatformException(
        'TIMEOUT',
        'macOS XCTest screenshot deadline exceeded',
        hint: 'The first capture builds an XCTest runner; allow --timeout 120000.',
      );
    }
  }

  Future<MacosScreenshot> _capture(int display, DateTime deadline) async {
    _check(deadline);
    if (_disposed) {
      throw const PlatformException('IO_ERROR', 'Screen capturer is closed');
    }
    if (display < 1 || display > 999) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Display must be 1 to 999',
      );
    }
    _permission();
    final before = displays();
    if (display > before.length) {
      throw const PlatformException(
        'TARGET_NOT_FOUND',
        'The selected display is not active',
      );
    }
    // XCTest exposes only main-first ordinals, not CoreGraphics identities.
    // With two screens the remaining screen is unambiguous; never guess among 3+.
    if (display != 1 && before.length > 2) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Public XCTest APIs cannot map secondary display IDs with more than two active displays',
      );
    }
    final selected = before[display - 1];
    final topology = jsonEncode(before.map((d) => d.toJson()).toList());
    if (selected.width <= 0 || selected.height <= 0) {
      throw const PlatformException(
        'TARGET_NOT_FOUND',
        'Display has no drawable area',
      );
    }
    await _run(['--find', 'xcodebuild'], deadline, sdkProbe: true);
    await _prepare(deadline);
    final work = await _build!.createTemp('capture-');
    final planPath =
        '${File(_testRun!).parent.path}/capture-${work.uri.pathSegments.where((s) => s.isNotEmpty).last}.xctestrun';
    try {
      final planJson = await _run(
        ['-convert', 'json', '-o', '-', _testRun!],
        deadline,
        executable: '/usr/bin/plutil',
      );
      final plan = jsonDecode(utf8.decode(planJson));
      var targets = 0;
      void configure(Object? node) {
        if (node is Map) {
          if (node.containsKey('TestBundlePath')) {
            targets++;
            (node['EnvironmentVariables'] ??= <String, dynamic>{}).addAll({
              'MRA_DISPLAY_INDEX': '$display',
              'MRA_DISPLAY_COUNT': '${before.length}',
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
      if (targets != 1) {
        throw const FormatException('Expected one XCTest target');
      }
      final jsonPath = '${work.path}/plan.json';
      await File(jsonPath).writeAsString(jsonEncode(plan));
      await _run(
        ['-convert', 'xml1', '-o', planPath, jsonPath],
        deadline,
        executable: '/usr/bin/plutil',
      );
      final result = '${work.path}/result.xcresult';
      await _run([
        'xcodebuild',
        'test-without-building',
        '-xctestrun',
        planPath,
        '-destination',
        'platform=macOS',
        '-parallel-testing-enabled',
        'NO',
        '-only-testing:ScreenCapture/Capture/testCapture',
        '-resultBundlePath',
        result,
      ], deadline);
      _permission();
      if (topology != jsonEncode(displays().map((d) => d.toJson()).toList())) {
        throw const PlatformException(
          'TARGET_NOT_FOUND',
          'Display configuration changed during capture',
        );
      }
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
      final records = jsonDecode(
        await File('$output/manifest.json').readAsString(),
      ) as List;
      final candidates = <String>[];
      for (final record in records) {
        if (record['testIdentifier'] != 'Capture/testCapture()') continue;
        for (final attachment in record['attachments'] as List) {
          if (attachment['isAssociatedWithFailure'] != false ||
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
        throw const FormatException('Expected one screen attachment');
      }
      final path = candidates.single;
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Expected regular image');
      }
      final image = File(path);
      final size = await image.length();
      if (size < 24 || size > 40 * 1024 * 1024) {
        throw const FormatException('Invalid image size');
      }
      final bytes = await image.readAsBytes();
      if (base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
          ascii.decode(bytes.sublist(12, 16)) != 'IHDR') {
        throw const FormatException('Invalid PNG');
      }
      final header = ByteData.sublistView(bytes);
      final pixelWidth = header.getUint32(16),
          pixelHeight = header.getUint32(20);
      if (pixelWidth == 0 || pixelHeight == 0) {
        throw const FormatException('Empty PNG');
      }
      _check(deadline);
      return MacosScreenshot(bytes, {
        'source': 'macos-xcuiscreen',
        'method': 'xcuiscreen',
        'scope': 'display',
        'displayIndex': display,
        'displayId': selected.id,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
        'bounds': {
          'x': selected.x,
          'y': selected.y,
          'width': selected.width,
          'height': selected.height,
          'unit': 'macos_global_points',
        },
        'scaleX': pixelWidth / selected.width,
        'scaleY': pixelHeight / selected.height,
        'includesOtherApplications': true,
      });
    } finally {
      await _terminate();
      await File(planPath).delete().catchError((Object _) => File(planPath));
      await work.delete(recursive: true).catchError((Object _) => work);
    }
  }

  Future<void> _prepare(DateTime deadline) async {
    if (_testRun != null) return;
    final root = temporaryRoot ?? Directory.systemTemp;
    final created = _build ?? await root.createTemp('mra-macos-xctest-');
    final directory = _build = Directory(await created.resolveSymbolicLinks());
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
        'platform=macOS',
        '-derivedDataPath',
        '${directory.path}/derived',
        'CODE_SIGN_IDENTITY=-',
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

  Future<Uint8List> _run(
    List<String> args,
    DateTime deadline, {
    bool sdkProbe = false,
    String? executable,
  }) async {
    _check(deadline);
    Process? process;
    try {
      final starting = Process.start(executable ?? xcrun, args);
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
              : 'Cannot run XCTest tool',
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

  Future<void> _terminate() async {
    if (_build == null) return;
    final executable =
        '${_build!.path}/derived/Build/Products/Debug/ScreenCapture-Runner.app/Contents/MacOS/ScreenCapture-Runner';
    try {
      final output = await _run(
        ['-ww', '-axo', 'pid=,args='],
        DateTime.now().add(const Duration(seconds: 3)),
        executable: '/bin/ps',
      );
      for (final line in utf8.decode(output).split('\n')) {
        final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
        if (match != null &&
            (match[2] == executable || match[2]!.startsWith('$executable '))) {
          Process.killPid(int.parse(match[1]!), ProcessSignal.sigkill);
        }
      }
    } catch (_) {
      /* Bound cleanup; never kill by a shared process name. */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _queue;
    await _terminate();
    if (_build != null) {
      await _build!.delete(recursive: true).catchError((Object _) => _build!);
    }
  }
}
