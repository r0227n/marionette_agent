import '../protocol/protocol.dart';
import '../session/session.dart';
import '../snapshot/snapshot_service.dart';
import '../output/content.dart';
import 'command_context.dart';
import 'registry.dart';

const batchCommands = {
  'snapshot',
  'get',
  'is',
  'find',
  'tap',
  'click',
  'fill',
  'type',
  'focus',
  'hover',
  'check',
  'uncheck',
  'select',
  'dblclick',
  'press',
  'keydown',
  'keyup',
  'keyboard',
  'clipboard',
  'scroll',
  'swipe',
  'scrollintoview',
  'drag',
  'wait',
  'logs',
};

List<Json> validateBatch(Json params) {
  final steps = params['steps'];
  if (params.length != 1 ||
      steps is! List ||
      steps.isEmpty ||
      steps.length > 100) {
    invalid('Batch requires 1 to 100 commands');
  }
  return steps.map((raw) {
    if (raw is! Map ||
        raw.length != 2 ||
        !batchCommands.contains(raw['command']) ||
        raw['params'] is! Map) {
      invalid('Unsupported batch command');
    }
    return {'command': raw['command'], 'params': asJson(raw['params'])};
  }).toList();
}

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
