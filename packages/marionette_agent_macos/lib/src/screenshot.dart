import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/host_support.dart';

import 'displays.dart';

/// Native pixels and capture-time metadata. Final encoding/persistence belongs
/// to the shared artifact writer, never to this OS service.
class MacosScreenshot {
  MacosScreenshot(this.png, this.metadata);
  final Uint8List png;
  final Map<String, Object?> metadata;
}

typedef CaptureProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

class MacosScreenshotService {
  const MacosScreenshotService({
    this.permission = screenCaptureAllowed,
    this.displays = activeMacosDisplays,
    this.start = Process.start,
  });
  final bool Function() permission;
  final List<MacosDisplay> Function() displays;
  final CaptureProcessStarter start;

  Future<MacosScreenshot> capture(int display, DateTime deadline) async {
    void check() {
      if (!deadline.isAfter(DateTime.now())) {
        throw const PlatformException(
          'TIMEOUT',
          'Screenshot deadline exceeded',
        );
      }
    }

    void checkPermission() {
      if (!permission()) {
        throw const PlatformException(
          'SCREEN_CAPTURE_PERMISSION_REQUIRED',
          'Screen Recording permission is not granted (denied or not requested)',
          hint: 'Enable Screen Recording for the terminal/host app in macOS System Settings, then explicitly retry. No permission prompt is requested.',
        );
      }
    }

    check();
    if (display < 1 || display > 999) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Display must be an integer from 1 to 999',
      );
    }
    checkPermission();
    final before = displays();
    if (display > before.length) {
      throw const PlatformException(
        'TARGET_NOT_FOUND',
        'The selected display is not active',
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
    Directory? staging;
    Process? process;
    var processExited = false;
    MacosScreenshot? screenshot;
    try {
      staging = await Directory.systemTemp.createTemp(
        'marionette-native-shot-',
      );
      final file = File('${staging.path}/screen.png');
      check();
      process = await start('/usr/sbin/screencapture', [
        '-x',
        '-t',
        'png',
        '-D',
        '$display',
        file.path,
      ]);
      final completed = Future.wait<Object?>([
        process.exitCode,
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ], eagerError: true);
      int code;
      try {
        final result = await completed.timeout(
          deadline.difference(DateTime.now()),
        );
        code = result.first as int;
        processExited = true;
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        // Reap before deleting staging so a late process cannot recreate it.
        await process.exitCode.timeout(const Duration(seconds: 5));
        processExited = true;
        throw const PlatformException('TIMEOUT', 'Native screenshot timed out');
      }
      check();
      checkPermission();
      if (topology != jsonEncode(displays().map((d) => d.toJson()).toList())) {
        throw const PlatformException(
          'TARGET_NOT_FOUND',
          'Display configuration changed during capture; explicitly select it again',
        );
      }
      if (code != 0) {
        throw const PlatformException(
          'IO_ERROR',
          'Native screenshot capture failed',
        );
      }
      // Bound IPC size before loading; final PNG decoding belongs to the writer.
      if (!await file.exists() || await file.length() > 40 * 1024 * 1024) {
        throw const PlatformException(
          'IO_ERROR',
          'Native screenshot is missing or too large',
        );
      }
      final bytes = await file.readAsBytes();
      check();
      if (bytes.length < 24 ||
          base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
          ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
        throw const PlatformException(
          'IO_ERROR',
          'Native capture did not return PNG',
        );
      }
      final header = ByteData.sublistView(bytes);
      final pixelWidth = header.getUint32(16),
          pixelHeight = header.getUint32(20);
      if (pixelWidth == 0 || pixelHeight == 0) {
        throw const PlatformException(
          'IO_ERROR',
          'Native screenshot has empty dimensions',
        );
      }
      screenshot = MacosScreenshot(bytes, {
        'source': 'macos-screencapture',
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
    } on PlatformException {
      rethrow;
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Native screenshot cleanup timed out',
      );
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot acquire native screenshot',
      );
    } finally {
      if (process != null && !processExited) {
        process.kill(ProcessSignal.sigkill);
        // Process normally already ended. Do not race deletion with a writer.
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {
          staging = null;
        }
      }
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {
          if (screenshot != null) {
            throw const PlatformException(
              'IO_ERROR',
              'Cannot clean up native screenshot staging',
            );
          }
        }
      }
    }
    check();
    return screenshot;
  }
}
