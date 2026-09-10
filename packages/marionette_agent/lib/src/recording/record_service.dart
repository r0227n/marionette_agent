import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../protocol/protocol.dart';

/// Adapts the utility API to CLI errors and result fields. No OS commands here.
class RecordService {
  RecordService({RecordingManager? manager})
    : manager = manager ?? RecordingManager();
  final RecordingManager manager;
  bool contains(String session) => manager.contains(session);

  Future<Json> handle(Request request) => _adapt(
    () async {
      final params = request.params;
      final action = params['action'];
      if (action == 'start') {
        final target = validateRecordStart(params);
        return manager.start(
          owner: request.session,
          target: target,
          path: params['path'] as String,
          deadline: request.deadline,
        );
      }
      if (params.length != 1) invalid('Unexpected recording arguments');
      if (action == 'status') return manager.status(request.session);
      if (action == 'stop') {
        return manager.stop(request.session, request.deadline);
      }
      invalid('Usage: record start|stop|status');
    },
    failureOutcome: request.params['action'] == 'stop'
        ? Outcome.failed
        : Outcome.notSent,
  );

  Future<Json?> close(Request request) async {
    if (!contains(request.session)) return null;
    return _adapt(
      () async => (await manager.close(request.session, request.deadline))!,
      failureOutcome: Outcome.failed,
    );
  }

  Future<Json> _adapt(
    Future<Json> Function() operation, {
    required Outcome failureOutcome,
  }) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      throw AgentError(
        error.code,
        error.message,
        hint: error.hint,
        outcome: error.code == 'TIMEOUT' ? Outcome.unknown : failureOutcome,
      );
    }
  }

  Future<void> dispose() => manager.dispose();
}

/// Shared CLI/IPC validation. Unsupported targets fail before runtime startup.
RecordingTarget validateRecordStart(Json params) {
  if (params.length != 4 ||
      params['action'] != 'start' ||
      params['platform'] is! String ||
      params['device'] is! String ||
      params['path'] is! String) {
    invalid('Invalid record start arguments');
  }
  final platform = RecordingPlatform.values
      .where((value) => value.name == params['platform'])
      .firstOrNull;
  if (platform == null) invalid('Unknown recording platform');
  final target = RecordingTarget(platform, params['device'] as String);
  try {
    validateTarget(target, params['path'] as String);
  } on PlatformException catch (error) {
    throw AgentError(error.code, error.message, hint: error.hint);
  }
  return target;
}
