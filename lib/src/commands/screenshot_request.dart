import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';

TargetQuery? screenshotTarget(Json params) {
  final platform = params.containsKey('platform')
      ? params['platform']
      : 'flutter';
  if (platform != 'flutter' && platform != 'android') {
    invalid('Screenshot platform must be flutter or android');
  }
  if (platform == 'android') {
    final device = params['device'];
    if (device is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$').hasMatch(device)) {
      invalid(
        'Android capture requires an explicit device serial; automatic selection is unsupported',
      );
    }
    if (params.containsKey('display') && params['display'] != '0') {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Only Android default display 0 is supported',
      );
    }
    if (params['annotate'] == true ||
        params.containsKey('ref') ||
        SelectorKind.values.any((k) => params.containsKey(k.name))) {
      invalid('Native screenshots do not support Flutter annotation or crop');
    }
  } else if (params.containsKey('device') || params.containsKey('display')) {
    invalid('Flutter screenshots do not accept device or display');
  }
  final target = {...params}
    ..remove('path')
    ..remove('annotate')
    ..remove('platform')
    ..remove('device')
    ..remove('display');
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
