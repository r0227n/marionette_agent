import 'dart:io';

import '../protocol/protocol.dart';
import 'artifact_writer.dart';
import 'common_options.dart';

/// Persist successful workflow captures with the standalone writer and caller
/// cwd/options. If saving fails, roll back only this invocation's new artifacts.
Future<Json> saveWorkflowScreenshots(
  Json data,
  CommonOptions options,
  DateTime deadline,
) async {
  final captures = data['screenshots'];
  if (captures is! List) return data;
  final saved = <Json>[];
  try {
    for (final raw in captures) {
      final capture = asJson(raw);
      final result = await saveScreenshots(
        capture,
        capture['path'] as String?,
        deadline,
        format: options.screenshotFormat,
        quality: options.screenshotQuality,
        screenshotDir: options.screenshotDir,
      );
      saved.add({'stepId': capture['stepId'], ...result});
    }
    return {...data, 'screenshots': saved};
  } on AgentError catch (error) {
    for (var i = 0; i < saved.length; i++) {
      for (final path in saved[i]['paths'] as List) {
        try {
          await File(path as String).delete();
        } catch (_) {
          /* Preserve error. */
        }
      }
      if ((captures[i] as Map)['path'] == null &&
          options.screenshotDir == null) {
        try {
          await File((saved[i]['paths'] as List).first as String).parent
              .delete();
        } catch (_) {
          /* Preserve error. */
        }
      }
    }
    throw AgentError(
      error.code,
      error.message,
      outcome: error.outcome,
      hint: 'Workflow execution completed; image saving failed. Do not replay UI actions automatically',
      details: {
        'workflow': data['workflow'],
        'progressKnown': true,
        'completedSteps': data['completedSteps'],
        'phase': 'screenshot-save',
      },
    );
  }
}
