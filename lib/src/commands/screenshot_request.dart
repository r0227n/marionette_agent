import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';

String screenshotSource(Json params) {
  final source = params.containsKey('source') ? params['source'] : 'flutter';
  if (!['flutter', 'macos'].contains(source)) {
    invalid('Expected screenshot source flutter or macos');
  }
  if (source == 'macos') {
    final display = params['display'];
    if (display is! int || display < 1 || display > 999) {
      invalid('macos source requires an explicit display from 1 to 999');
    }
    if (params['annotate'] == true ||
        params.containsKey('ref') ||
        SelectorKind.values.any((kind) => params.containsKey(kind.name))) {
      invalid(
        'Native display screenshots do not support Flutter annotation or crop',
      );
    }
  } else if (params.containsKey('display')) {
    invalid('Display is only valid with source macos');
  }
  return source as String;
}

TargetQuery? screenshotTarget(Json params) {
  screenshotSource(params);
  final target = {...params}
    ..remove('path')
    ..remove('annotate')
    ..remove('source')
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
