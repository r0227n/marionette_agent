import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Default-display Emulator capture. Never requests authorization or falls back
/// to app rendering. PNG decoding and persistence belong to the shared writer.
class AndroidScreenCapturer implements ScreenCapturer {
  const AndroidScreenCapturer({this.adb = 'adb'});
  final String adb;

  @override
  Future<CapturedScreen> capture(String device, DateTime deadline) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$').hasMatch(device)) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Invalid Android serial',
      );
    }
    final inventory = utf8.decode(await _run(['devices', '-l'], deadline));
    final rows = inventory
        .split('\n')
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((row) => row.length >= 2 && row.first == device)
        .toList();
    if (rows.length != 1) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'The selected Android serial is not uniquely present in adb devices',
      );
    }
    switch (rows.single[1]) {
      case 'unauthorized':
        throw const PlatformException(
          'IO_ERROR',
          'The selected Android device is unauthorized',
          hint: 'Authorize debugging on the device; authorization is never changed automatically',
        );
      case 'offline':
        throw const PlatformException(
          'CONNECTION_LOST',
          'The selected Android device is offline',
        );
      case 'device':
        break;
      default:
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'The selected Android device is not ready',
        );
    }
    final prefix = ['-s', device];
    final emulator = utf8
        .decode(
          await _run([
            ...prefix,
            'shell',
            'getprop',
            'ro.kernel.qemu',
          ], deadline),
        )
        .trim();
    if (!RegExp(r'^emulator-[0-9]+$').hasMatch(device) || emulator != '1') {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Native Android screenshots currently support Android Emulator only',
      );
    }
    // Fail closed if display topology is unknown or includes a secondary display.
    // Do not infer Flutter geometry or select an arbitrary physical display ID.
    final displays = utf8.decode(
      await _run([...prefix, 'shell', 'dumpsys', 'display'], deadline),
    );
    final ids = RegExp(r'\bmDisplayId=\s*(\d+)\b')
        .allMatches(displays)
        .map((m) => m[1]!)
        .toSet();
    if (ids.length != 1 || ids.single != '0') {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Native capture requires a verifiable single default display; multiple displays are unsupported',
      );
    }
    final png = await _run(
      [...prefix, 'exec-out', 'screencap', '-p'],
      deadline,
      limit: 32 * 1024 * 1024,
    );
    return CapturedScreen(
      png,
      source: 'android-adb',
      device: device,
      display: 0,
    );
  }

  Future<Uint8List> _run(
    List<String> args,
    DateTime deadline, {
    int limit = 1024 * 1024,
  }) async {
    void check() {
      if (!deadline.isAfter(DateTime.now())) {
        throw const PlatformException(
          'TIMEOUT',
          'Android screenshot deadline exceeded',
        );
      }
    }

    check();
    Process? process;
    StreamSubscription<List<int>>? output, errors;
    try {
      final starting = Process.start(adb, args);
      try {
        process = await starting.timeout(deadline.difference(DateTime.now()));
      } on TimeoutException {
        unawaited(
          starting
              .then((late) async {
                late.kill(ProcessSignal.sigkill);
                await Future.wait([
                  late.stdout.drain<void>(),
                  late.stderr.drain<void>(),
                  late.exitCode,
                ]);
              })
              .catchError((Object _) {}),
        );
        rethrow;
      }
      await process.stdin.close();
      final bytes = BytesBuilder(copy: false);
      final stderr = BytesBuilder(copy: false);
      final done = Completer<void>();
      final errorsDone = Completer<void>();
      output = process.stdout.listen(
        (chunk) {
          if (bytes.length + chunk.length > limit) {
            if (!done.isCompleted) {
              done.completeError(
                const PlatformException(
                  'IO_ERROR',
                  'Android screenshot output exceeds the limit',
                ),
              );
            }
            process!.kill(ProcessSignal.sigkill);
          } else {
            bytes.add(chunk);
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error) {
          if (!done.isCompleted) done.completeError(error);
        },
      );
      errors = process.stderr.listen(
        (chunk) {
          if (stderr.length < 8192) {
            stderr.add(chunk.take(8192 - stderr.length).toList());
          }
        },
        onDone: () => errorsDone.complete(),
        onError: (Object error) => errorsDone.completeError(error),
      );
      final completion = await Future.wait<Object?>([
        process.exitCode,
        done.future,
        errorsDone.future,
      ]).timeout(deadline.difference(DateTime.now()));
      check();
      if (completion.first != 0) {
        final reason = utf8
            .decode(stderr.takeBytes(), allowMalformed: true)
            .toLowerCase();
        if (reason.contains('unauthorized')) {
          throw const PlatformException(
            'IO_ERROR',
            'The selected Android device is unauthorized',
          );
        }
        if (reason.contains('offline') ||
            reason.contains('not found') ||
            reason.contains('disconnected')) {
          throw const PlatformException(
            'CONNECTION_LOST',
            'The selected Android device disconnected or went offline',
          );
        }
        if (reason.contains('permission denied') ||
            reason.contains('secure') ||
            reason.contains('not allowed')) {
          throw const PlatformException(
            'IO_ERROR',
            'Android denied screen capture; protected content cannot be captured',
          );
        }
        throw const PlatformException(
          'IO_ERROR',
          'Android screen capture command failed',
        );
      }
      return bytes.takeBytes();
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Android screenshot deadline exceeded',
      );
    } on ProcessException {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Cannot start adb',
        hint:
            'Install Android SDK platform-tools and make adb available on PATH',
      );
    } on PlatformException {
      rethrow;
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot read Android screen capture output',
      );
    } finally {
      // Own only this adb client process. Never kill/restart the adb server.
      process?.kill(ProcessSignal.sigkill);
      await output?.cancel();
      await errors?.cancel();
      if (process != null) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          /* bounded cleanup */
        }
      }
    }
  }
}
