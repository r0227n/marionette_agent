import 'dart:io';

import 'package:path/path.dart' as p;

/// Keep screenshots from each run separate, even when the report path is reused.
Future<Directory> createEvidenceDirectory(String report, String prefix) async {
  final parent = Directory(p.dirname(p.absolute(report)));
  await parent.create(recursive: true);
  return parent.createTemp('$prefix-');
}

/// Still screenshots observe a selected Simulator, independently of app URI.
/// Manual smoke callers set this explicitly; a Flutter connection is insufficient.
List<String> nativeScreenshotArguments(List<String> args) {
  final index = args.indexOf('screenshot');
  if (index < 0 ||
      args.contains('--device') ||
      args.any((a) => a.startsWith('--device='))) {
    return args;
  }
  final device =
      Platform.environment['MARIONETTE_TEST_DEVICE'] ??
      Platform.environment['SIMULATOR_UDID'];
  if (device == null || device.isEmpty) {
    throw ArgumentError(
      'Set MARIONETTE_TEST_DEVICE to the selected booted iOS Simulator UDID',
    );
  }
  return [...args.take(index + 1), '--device', device, ...args.skip(index + 1)];
}
