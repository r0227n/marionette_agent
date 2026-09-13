import 'dart:async';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart' show SelectorQuery, RefQuery;
import 'arguments.dart';
import 'command_context.dart';

const defaultWaitState = 'exists';
const defaultWaitPollIntervalMs = 100;
const minimumWaitPollIntervalMs = 50;
const maximumWaitPollIntervalMs = 1000;

/// Shared standalone/workflow handler. It never publishes refs or retries UI actions.
Future<Json> handleWait(CommandContext context, Json params) async {
  if (params.containsKey('milliseconds')) {
    final ms = params['milliseconds'];
    if (params.length != 1 || ms is! int || ms < 0) {
      invalid('Invalid wait duration');
    }
    parseDurationMs('$ms', allowZero: true);
    // Read boundary applies the same connection and absolute deadline contract.
    await context.read((_) => Future<void>.delayed(Duration(milliseconds: ms)));
    return {'waitedMs': ms, 'requiresSnapshot': false};
  }
  if (params.containsKey('ref')) {
    final ref = params['ref'];
    if (ref is! String) invalid('Invalid wait ref');
    if (params.keys.any(
      (key) => !{'ref', 'state', 'pollIntervalMs'}.contains(key),
    )) {
      invalid('Invalid wait ref arguments');
    }
    WaitRequest.parse({
      'key': 'validation-only',
      if (params.containsKey('state')) 'state': params['state'],
      if (params.containsKey('pollIntervalMs'))
        'pollIntervalMs': params['pollIntervalMs'],
    });
    final query = RefQuery(ref);
    final selector = await context.referenceSelector(query);
    if ((params['state'] ?? 'exists') == 'exists') {
      await context.observeTarget(query);
    }
    params = {...params}..remove('ref');
    params.addAll(selector.toJson());
  }
  final request = WaitRequest.parse(params);
  await waitForTarget(context, request);
  return {'state': request.state, 'requiresSnapshot': true};
}

Future<void> waitForTarget(CommandContext context, WaitRequest request) async {
  final selector = request.selector;
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

class WaitRequest {
  const WaitRequest(this.selector, this.state, this.pollIntervalMs);

  final Selector selector;
  final String state;
  final int pollIntervalMs;

  static WaitRequest parse(Json params) {
    final allowed = {
      ...SelectorKind.values.map((kind) => kind.name),
      'state',
      'pollIntervalMs',
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown wait parameter');
    }
    final state = params['state'] ?? defaultWaitState;
    if (state != 'exists' && state != 'gone') {
      invalid('Wait state must be exists or gone');
    }
    final interval = params['pollIntervalMs'] ?? defaultWaitPollIntervalMs;
    if (interval is! int ||
        interval < minimumWaitPollIntervalMs ||
        interval > maximumWaitPollIntervalMs) {
      invalid('Poll interval must be an integer from 50 to 1000');
    }
    final target = <String, Object?>{
      for (final kind in SelectorKind.values)
        if (params.containsKey(kind.name)) kind.name: params[kind.name],
    };
    return WaitRequest(
      (decodeTarget(target) as SelectorQuery).selector,
      state as String,
      interval,
    );
  }

  Json toJson() => {
    ...selector.toJson(),
    'state': state,
    'pollIntervalMs': pollIntervalMs,
  };
}
