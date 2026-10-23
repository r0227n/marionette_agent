import 'dart:io';

import '../protocol/protocol.dart';
import 'artifact_writer.dart';
import 'common_options.dart';

Future<Json> saveWorkflowScreenshots(
  Json data,
  CommonOptions options,
  DateTime deadline,
) async {
  if (data['screenshots'] == null) return data;
  final saved = <Json>[];
  final cleanup = <File>[];
  final directories = <Directory>{};
  try {
    for (final raw in data['screenshots'] as List) {
      final capture = asJson(raw);
      final result = await saveScreenshots(
        asJson(capture['data']),
        capture['path'] as String?,
        deadline,
        screenshotDir: options.screenshotDir,
        format: options.screenshotFormat,
        quality: options.screenshotQuality,
      );
      for (final path in (result['paths'] as List).cast<String>()) {
        final file = File(path);
        cleanup.add(file);
        if (capture['path'] == null && options.screenshotDir == null) {
          directories.add(file.parent);
        }
      }
      saved.add({'stepId': capture['stepId'], ...result});
    }
    return {...data, 'screenshots': saved};
  } catch (error) {
    for (final file in cleanup) {
      try {
        await file.delete();
      } catch (_) {
        /* keep original error */
      }
    }
    for (final directory in directories) {
      try {
        await directory.delete();
      } catch (_) {
        /* keep original error */
      }
    }
    if (error is AgentError) {
      throw AgentError(
        error.code,
        error.message,
        hint: 'Screenshot saving failed after workflow execution; do not replay UI actions',
        outcome: error.outcome,
        details: {
          'workflow': data['workflow'],
          'completedSteps': data['completedSteps'],
          'progressKnown': true,
          'phase': 'screenshot-save',
        },
      );
    }
    rethrow;
  }
}
