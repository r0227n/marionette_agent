import 'dart:async';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../workflow/model.dart';
import 'command_context.dart';

/// Workflow-only observation loop. Never publishes refs or retries UI actions.
Future<Json> waitForTarget(CommandContext context, WorkflowStep step) async {
  final selector = step.selector!;
  while (true) {
    final elements = await context.read((backend) => backend.inspect());
    final matches = elements
        .where((e) => e.candidateValue(selector.kind) == selector.value)
        .toList();
    context.check();
    if (matches.length == 1 &&
        selector.kind == SelectorKind.text &&
        !matches.single.textMatchable) {
      throw const AgentError(
        'UNRESOLVABLE_TARGET',
        'Displayed text does not map to a backend text matcher',
      );
    }
    if (step.state == 'exists' && matches.length > 1) {
      throw const AgentError('AMBIGUOUS_TARGET', 'Multiple elements match');
    }
    if (step.state == 'gone'
        ? matches.isEmpty
        : matches.length == 1 && matches.single.visible != false) {
      return {};
    }
    // Execution.read checks parent cancellation/deadlines after every awaited poll.
    await context.read(
      (_) => Future<void>.delayed(Duration(milliseconds: step.pollIntervalMs)),
    );
  }
}
