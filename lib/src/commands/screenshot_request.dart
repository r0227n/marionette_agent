import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';

const screenshotSources = ['flutter', 'ios-simulator', 'ios-device'];

/// Shared CLI, IPC, and workflow validation, independent of execution state.
TargetQuery? screenshotTarget(Json params) {
  final source = params['source'] ?? 'flutter';
  if ((params.containsKey('source') && params['source'] is! String) ||
      !screenshotSources.contains(source) ||
      (params.containsKey('annotate') && params['annotate'] is! bool) ||
      (params.containsKey('path') &&
          (params['path'] is! String ||
              (params['path'] as String).isEmpty ||
              (params['path'] as String).contains('\u0000')))) {
    invalid('Invalid screenshot arguments');
  }
  final target = {...params}
    ..remove('path')
    ..remove('annotate')
    ..remove('source')
    ..remove('device');
  if (source == 'flutter') {
    if (params.containsKey('device')) {
      invalid('Flutter capture uses the connected session');
    }
  } else {
    final device = params['device'];
    if (device is! String || device.isEmpty || device.contains('\u0000')) {
      invalid('Native capture requires an explicit device');
    }
    if (source == 'ios-simulator' &&
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(device)) {
      invalid('Specify a Simulator UDID, never a name or booted');
    }
    if (target.isNotEmpty || params['annotate'] == true) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Native screenshots do not support Flutter ref annotation or element crop',
      );
    }
  }
  if (target.isEmpty) return null;
  if (params['annotate'] == true) {
    invalid('Crop and annotation cannot be combined');
  }
  if (target.keys.any(
    (key) =>
        key != 'ref' && !SelectorKind.values.any((kind) => kind.name == key),
  )) {
    invalid('Invalid screenshot target');
  }
  return decodeTarget(target);
}

bool isNativeScreenshot(String command, Json params) =>
    command == 'screenshot' &&
    ['ios-simulator', 'ios-device'].contains(params['source']);
