import '../protocol/protocol.dart';
import '../session/session.dart';
import '../snapshot/snapshot_service.dart';
import '../output/content.dart';
import 'command_context.dart';
import 'registry.dart';

import 'batch_request.dart';

export 'batch_request.dart';

/// One session queue entry, one Execution per step. Never replay completed UI actions.
Future<Json> executeBatch(
  Request request,
  Session session,
  SnapshotService snapshots,
  CommandRegistry commands,
) async {
  final steps = validateBatch(request.params);
  final results = <Json>[];
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    final child = Request(
      requestId: request.requestId,
      session: request.session,
      command: step['command'] as String,
      params: asJson(step['params']),
      deadline: request.deadline,
      debug: request.debug,
      maxOutput: request.maxOutput,
      outputJson: request.outputJson,
    );
    final execution = Execution(child, session);
    try {
      final data = limitContent(
        await execution.bound(
          () => commands.dispatch(
            CommandContext(execution, snapshots),
            child.command,
            child.params,
          ),
        ),
        request.maxOutput,
        request.outputJson,
      );
      snapshots.retainPublished(session, data);
      results.add({'command': child.command, 'data': data});
    } on AgentError catch (error) {
      throw AgentError(
        error.code,
        error.message,
        hint: error.hint,
        outcome: error.outcome,
        details: {
          'completed': index,
          'failedIndex': index,
          'results': results,
          'progressKnown': true,
        },
      );
    }
  }
  return {'completed': steps.length, 'results': results};
}
