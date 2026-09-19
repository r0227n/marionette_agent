import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../protocol/protocol.dart';
import '../backend/backend.dart';
import '../backend/flutter_recorder.dart';

/// Adapts the utility API to CLI errors and result fields. No OS commands here.
class RecordService {
  RecordService({RecordingManager? manager})
    : manager = manager ?? RecordingManager();
  final RecordingManager manager;
  bool contains(String session) => manager.contains(session);

  Future<Json> handle(Request request, {Backend? backend, Uri? uri}) => _adapt(
    () async {
      final params = request.params;
      final action = params['action'];
      if (action == 'start' || action == 'restart') {
        var target = validateRecordStart(params);
        ScreenRecorder? recorder;
        if (target.platform == RecordingPlatform.flutter) {
          if (uri == null || backend == null) {
            throw const AgentError(
              'NOT_CONNECTED',
              'Connect before recording Flutter frames',
            );
          }
          if (backend is! ScreenshotConnectionBackend) {
            throw const AgentError(
              'UNSUPPORTED_CAPABILITY',
              'Backend cannot record application frames',
            );
          }
          target = RecordingTarget(
            RecordingPlatform.flutter,
            request.session,
            fps: target.fps,
          );
          recorder = FlutterScreenRecorder(
            backend as ScreenshotConnectionBackend,
            uri,
          );
        }
        if (action == 'restart') {
          if (await FileSystemEntity.type(
                params['path'] as String,
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound) {
            throw const AgentError(
              'IO_ERROR',
              'Restart requires a new output path',
            );
          }
          await manager.stop(request.session, request.deadline);
        }
        return manager.start(
          owner: request.session,
          target: target,
          path: params['path'] as String,
          deadline: request.deadline,
          recorder: recorder,
        );
      }
      if (params.length != 1) invalid('Unexpected recording arguments');
      if (action == 'status') return manager.status(request.session);
      if (action == 'stop') {
        return manager.stop(request.session, request.deadline);
      }
      invalid('Usage: record start|stop|status');
    },
    failureOutcome: ['stop', 'restart'].contains(request.params['action'])
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
  if (params.length != (params.containsKey('fps') ? 5 : 4) ||
      !['start', 'restart'].contains(params['action']) ||
      (params.containsKey('fps') &&
          (params['fps'] is! int ||
              (params['fps'] as int) < 1 ||
              (params['fps'] as int) > 60)) ||
      params['platform'] is! String ||
      params['device'] is! String ||
      params['path'] is! String) {
    invalid('Invalid record start arguments');
  }
  final platform = RecordingPlatform.values
      .where((value) => value.name == params['platform'])
      .firstOrNull;
  if (platform == null) invalid('Unknown recording platform');
  if (platform == RecordingPlatform.flutter && params['device'] != 'session') {
    invalid('Flutter recording uses the connected session');
  }
  final target = RecordingTarget(
    platform,
    params['device'] as String,
    fps: params['fps'] as int?,
  );
  try {
    validateTarget(target, params['path'] as String);
  } on PlatformException catch (error) {
    throw AgentError(error.code, error.message, hint: error.hint);
  }
  return target;
}
