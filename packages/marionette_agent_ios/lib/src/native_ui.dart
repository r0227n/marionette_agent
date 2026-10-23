import 'dart:convert';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/host_support.dart';

/// idb reads system accessibility and injects HID events without Computer use.
class IosNativeUi implements NativeUiBackend {
  const IosNativeUi({
    this.idb = 'idb',
    this.xcrun = 'xcrun',
    this.run = runNativeProcess,
  });
  final String idb, xcrun;
  final NativeProcessRunner run;

  @override
  Future<List<NativeElement>> inspect(String device, DateTime deadline) async {
    final output = await run(idb, [
      'ui',
      'describe-all',
      '--udid',
      device,
      '--json',
    ], deadline);
    return decodeIosNativeElements(nativeOutput(output));
  }

  @override
  Future<void> tap(String device, double x, double y, DateTime deadline) async {
    await run(idb, [
      'ui',
      'tap',
      '--udid',
      device,
      '${x.round()}',
      '${y.round()}',
    ], deadline);
  }

  @override
  Future<void> swipe(
    String device,
    double startX,
    double startY,
    double endX,
    double endY,
    DateTime deadline,
  ) async {
    await run(idb, [
      'ui',
      'swipe',
      '--udid',
      device,
      '${startX.round()}',
      '${startY.round()}',
      '${endX.round()}',
      '${endY.round()}',
      '--duration',
      '0.3',
    ], deadline);
  }

  @override
  Future<Uint8List> screenshot(String device, DateTime deadline) => run(xcrun, [
    'simctl',
    'io',
    device,
    'screenshot',
    '--type=png',
    '-',
  ], deadline);
}

List<NativeElement> decodeIosNativeElements(String text) {
  try {
    final rows = jsonDecode(text) as List;
    return rows.map((raw) {
      final row = raw as Map;
      final frame = row['frame'] as Map;
      if ([
        'x',
        'y',
        'width',
        'height',
      ].any((key) => frame[key] is! num || !(frame[key] as num).isFinite)) {
        throw const FormatException();
      }
      String? optional(String key) => switch (row[key]) {
        null => null,
        final String s => s.isEmpty ? null : s,
        _ => throw const FormatException(),
      };
      return NativeElement(
        type: row['type'] as String,
        text: optional('AXLabel'),
        identifier: optional('AXUniqueId'),
        value: optional('AXValue'),
        enabled: row['enabled'] as bool,
        bounds: NativeBounds(
          (frame['x'] as num).toDouble(),
          (frame['y'] as num).toDouble(),
          (frame['width'] as num).toDouble(),
          (frame['height'] as num).toDouble(),
        ),
      );
    }).toList();
  } catch (_) {
    throw const PlatformException(
      'BACKEND_ERROR',
      'Invalid iOS accessibility output',
    );
  }
}
