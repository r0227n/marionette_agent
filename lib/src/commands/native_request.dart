import '../protocol/protocol.dart';

/// Shared CLI/IPC validation, including device syntax before invoking any tool.
void validateNative(Json params) {
  final action = params['action'];
  final platform = params['platform'];
  final device = params['device'];
  if (!['snapshot', 'tap', 'swipe'].contains(action) ||
      !['ios', 'android'].contains(platform) ||
      device is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(device) ||
      (platform == 'ios' &&
          !RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
              .hasMatch(device))) {
    invalid(
      'Device binding requires --platform ios|android and an explicit --device id',
    );
  }
  final allowed = <String>{'action', 'platform', 'device'};
  switch (action) {
    case 'tap':
      allowed.addAll(['ref', 'text', 'identifier', 'type', 'x', 'y']);
      final selectors = [
        'ref',
        'text',
        'identifier',
        'type',
      ].where(params.containsKey).toList();
      final coordinates = params.containsKey('x') || params.containsKey('y');
      if (coordinates ? selectors.isNotEmpty : selectors.length != 1) {
        invalid(
          'Native tap requires one ref, exact selector, or coordinate pair',
        );
      }
      for (final key in selectors) {
        if (params[key] is! String || (params[key] as String).isEmpty) {
          invalid();
        }
      }
      if (params.containsKey('ref') &&
          !RegExp(r'^@n[1-9][0-9]*$').hasMatch(params['ref'] as String)) {
        invalid('Native refs have the form @n1; Flutter refs are not accepted');
      }
      if (coordinates) {
        nativeCoordinate(params['x']);
        nativeCoordinate(params['y']);
      }
    case 'swipe':
      if (params.containsKey('direction')) {
        final target = {...params}
          ..remove('direction')
          ..remove('distance');
        validateNative({...target, 'action': 'tap'});
        if (params.containsKey('x') ||
            !['left', 'right', 'up', 'down'].contains(params['direction']) ||
            nativeCoordinate(params['distance'] ?? 200) <= 0) {
          invalid('Invalid native swipe');
        }
        return;
      }
      allowed.addAll(['startX', 'startY', 'endX', 'endY']);
      for (final key in ['startX', 'startY', 'endX', 'endY']) {
        nativeCoordinate(params[key]);
      }
      if (params['startX'] == params['endX'] &&
          params['startY'] == params['endY']) {
        invalid('Swipe endpoints must differ');
      }
  }
  if (params.keys.any((key) => !allowed.contains(key))) {
    invalid('Unknown native field');
  }
}

double nativeCoordinate(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 10000000) {
    invalid('Native coordinates must be finite numbers from 0 to 10000000');
  }
  return value.toDouble();
}

/// Source selection never changes the interpretation of an existing ref.
Json validateUiSource(Json params) {
  final source = params['source'];
  if (params.containsKey('source') && !['flutter', 'native'].contains(source)) {
    invalid('Expected source flutter or native');
  }
  final ref = params['ref'];
  if (source != null &&
      ref is String &&
      ((ref.startsWith('@n') && source != 'native') ||
          (ref.startsWith('@e') && source != 'flutter'))) {
    invalid('Source conflicts with ref');
  }
  return {...params}..remove('source');
}
