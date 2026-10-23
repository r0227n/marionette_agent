import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Captures only an explicitly identified iOS Simulator's internal display.
/// No VM Service, UI interaction, auto-boot, retries, or rendering fallback.
class IosScreenCapturer implements ScreenCapturer {
  IosScreenCapturer({this.xcrun = '/usr/bin/xcrun', bool? isMacOS})
    : _isMacOS = isMacOS ?? Platform.isMacOS;

  final String xcrun;
  final bool _isMacOS;
  static final _udid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  Future<DeviceScreenshot> capture(String device, DateTime deadline) async {
    if (!_udid.hasMatch(device)) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Specify a Simulator UDID, never a name or booted',
      );
    }
    if (!_isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'iOS Simulator capture requires macOS/Xcode',
      );
    }
    await _run(['--find', 'simctl'], deadline, sdkProbe: true);
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
        final runtime = entry.key as String;
        if (!runtime.startsWith('com.apple.CoreSimulator.SimRuntime.iOS-')) {
          continue;
        }
        for (final raw in entry.value as List) {
          final item = raw as Map;
          if ((item['udid'] as String).toUpperCase() == device.toUpperCase() &&
              item['isAvailable'] != false) {
            matches.add((
              device: item['udid'] as String,
              runtime: runtime,
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
        hint: 'Use an available, booted iOS Simulator UDID in the default device set; physical devices are unsupported',
      );
    }
    final selected = matches.single;
    final png = await _run([
      'simctl',
      'io',
      selected.device,
      'screenshot',
      '--type=png',
      '--display=internal',
      '--mask=ignored',
      '-',
    ], deadline);
    return DeviceScreenshot(
      png: png,
      source: 'ios-simulator',
      device: selected.device,
      runtime: selected.runtime,
      display: 'internal',
      mask: 'ignored',
    );
  }

  // Binary stdout avoids temporary image files. Drain stderr without exposing
  // OS messages. Every process and pipe shares the original caller deadline.
  Future<Uint8List> _run(
    List<String> args,
    DateTime deadline, {
    bool sdkProbe = false,
  }) async {
    Duration remaining() {
      final value = deadline.difference(DateTime.now());
      if (value <= Duration.zero) throw TimeoutException('capture');
      return value;
    }

    Process? process;
    try {
      remaining();
      final starting = Process.start(xcrun, args);
      try {
        process = await starting.timeout(remaining());
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
      final output = child.stdout.forEach((chunk) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024) {
          child.kill(ProcessSignal.sigkill);
          throw const PlatformException(
            'IO_ERROR',
            'Native capture output exceeds 32 MiB',
          );
        }
        bytes.add(chunk);
      });
      final results = await Future.wait<Object?>([
        child.exitCode,
        output,
        child.stderr.drain<void>(),
      ], eagerError: true).timeout(remaining());
      remaining();
      if (results.first != 0) {
        throw PlatformException(
          sdkProbe ? 'UNSUPPORTED_CAPABILITY' : 'IO_ERROR',
          sdkProbe
              ? 'Xcode simctl is unavailable'
              : 'Native Simulator capture failed',
        );
      }
      return bytes.takeBytes();
    } on PlatformException {
      rethrow;
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Native screenshot deadline exceeded',
      );
    } on ProcessException {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Xcode simctl is unavailable',
      );
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'Native Simulator capture failed',
      );
    } finally {
      process?.kill(ProcessSignal.sigkill);
    }
  }
}
