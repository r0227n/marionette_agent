import 'dart:async';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'command_context.dart';

import 'wait_request.dart';

export 'wait_request.dart';

/// Parsing completes before any ref lookup, observation or delay.
Future<Json> handleWait(CommandContext context, Json params) async {
  final request = WaitRequest.parse(params);
  if (request is DurationWait) {
    await context.read(
      (_) => Future<void>.delayed(Duration(milliseconds: request.milliseconds)),
    );
    return {'waitedMs': request.milliseconds, 'requiresSnapshot': false};
  }
  final condition = request as TargetWait;
  final Selector selector;
  switch (condition.target) {
    case RefQuery query:
      selector = await context.referenceSelector(query);
      if (condition.state == 'exists') await context.observeTarget(query);
    case SelectorQuery query:
      selector = query.selector;
    case ObservedQuery():
      throw StateError('Wait requires a public target');
  }
  await waitForTarget(context, selector, condition);
  return {'state': condition.state, 'requiresSnapshot': true};
}

Future<void> waitForTarget(
  CommandContext context,
  Selector selector,
  TargetWait request,
) async {
  while (true) {
    final elements = await context.read((backend) {
      if (!backend.selectors.contains(selector.kind)) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Unsupported wait selector',
        );
      }
      return backend.inspect();
    });
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
    if (request.state == 'exists' && matches.length > 1) {
      throw const AgentError('AMBIGUOUS_TARGET', 'Multiple elements match');
    }
    if (request.state == 'gone'
        ? matches.isEmpty
        : matches.length == 1 && matches.single.visible != false) {
      return;
    }
    // Execution.read checks parent cancellation/deadlines after every awaited poll.
    await context.read(
      (_) =>
          Future<void>.delayed(Duration(milliseconds: request.pollIntervalMs)),
    );
  }
}
