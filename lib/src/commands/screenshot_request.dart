import '../protocol/protocol.dart';

/// Native screenshot validation shared by CLI, IPC, workflow and diff.
void screenshotTarget(Json params) {
  if (params.keys.any(
        (key) => !['path', 'platform', 'device', 'display'].contains(key),
      ) ||
      (params.containsKey('platform') && params['platform'] != 'android') ||
      params['device'] is! String ||
      (params['device'] as String).isEmpty ||
      (params['device'] as String).contains('\u0000') ||
      (params.containsKey('path') &&
          (params['path'] is! String || (params['path'] as String).isEmpty))) {
    invalid(
      'Screenshot requires --device <private UI Automator pairing file>; Flutter capture, annotation and crop are removed',
    );
  }
  if (params.containsKey('display') && params['display'] != '0') {
    throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'Only Android display 0 is supported',
    );
  }
}
