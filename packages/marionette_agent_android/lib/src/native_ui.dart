import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:xml/xml.dart';

class AndroidNativeUi implements NativeUiBackend {
  const AndroidNativeUi({this.adb = 'adb', this.run = runNativeProcess});
  final String adb;
  final NativeProcessRunner run;

  @override
  Future<List<NativeElement>> inspect(String device, DateTime deadline) async {
    // /dev/tty avoids a shared/stale dump file and needs no storage permission.
    final output = await run(adb, [
      '-s',
      device,
      'exec-out',
      'uiautomator',
      'dump',
      '/dev/tty',
    ], deadline);
    return decodeAndroidNativeElements(nativeOutput(output));
  }

  @override
  Future<void> tap(String device, double x, double y, DateTime deadline) async {
    await run(adb, [
      '-s',
      device,
      'shell',
      'input',
      'tap',
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
    await run(adb, [
      '-s',
      device,
      'shell',
      'input',
      'swipe',
      '${startX.round()}',
      '${startY.round()}',
      '${endX.round()}',
      '${endY.round()}',
      '300',
    ], deadline);
  }

  @override
  Future<Uint8List> screenshot(String device, DateTime deadline) =>
      run(adb, ['-s', device, 'exec-out', 'screencap', '-p'], deadline);
}

List<NativeElement> decodeAndroidNativeElements(String text) {
  try {
    final start = text.indexOf('<?xml');
    final end = text.lastIndexOf('</hierarchy>');
    if (start < 0 || end < start) throw const FormatException();
    final doc = XmlDocument.parse(text.substring(start, end + 12));
    if (doc.rootElement.name.local != 'hierarchy') {
      throw const FormatException();
    }
    return doc.findAllElements('node').map((node) {
      String? optional(String name) {
        final value = node.getAttribute(name);
        return value == null || value.isEmpty ? null : value;
      }

      final match = RegExp(r'^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$')
          .firstMatch(node.getAttribute('bounds') ?? '');
      if (match == null ||
          !['true', 'false'].contains(node.getAttribute('enabled'))) {
        throw const FormatException();
      }
      final x = double.parse(match[1]!), y = double.parse(match[2]!);
      final right = double.parse(match[3]!), bottom = double.parse(match[4]!);
      if (![x, y, right, bottom].every((v) => v.isFinite)) {
        throw const FormatException();
      }
      return NativeElement(
        type: node.getAttribute('class')!,
        text: optional('text') ?? optional('content-desc'),
        identifier: optional('resource-id'),
        value: optional('content-desc'),
        package: optional('package'),
        enabled: node.getAttribute('enabled') == 'true',
        bounds: NativeBounds(x, y, right - x, bottom - y),
      );
    }).toList();
  } catch (_) {
    throw const PlatformException(
      'BACKEND_ERROR',
      'Invalid Android accessibility output',
    );
  }
}
