import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';

import '../protocol/protocol.dart';
import '../commands/batch.dart';
import '../workflow/model.dart';
import 'session.dart';

const policyActions = {
  'tap',
  'click',
  'fill',
  'swipe',
  'scroll',
  'dblclick',
  'type',
  'focus',
  'hover',
  'check',
  'uncheck',
  'select',
  'scrollintoview',
  'press',
  'keydown',
  'keyup',
  'keyboard',
  'clipboard',
  'drag',
  'record',
  'workflow',
  'batch',
};

Json validatePolicy(Json policy) {
  if (policy.keys.any(
    (key) => !{'allow', 'deny', 'confirm', 'default'}.contains(key),
  )) {
    invalid('Unknown action policy field');
  }
  if (policy.containsKey('default') &&
      !['allow', 'deny'].contains(policy['default'])) {
    invalid('Policy default must be allow or deny');
  }
  for (final key in ['allow', 'deny', 'confirm']) {
    final values = policy[key];
    if (values != null &&
        (values is! List ||
            values.any(
              (value) => value is! String || !policyActions.contains(value),
            ))) {
      invalid('Policy lists must contain supported action names');
    }
  }
  return asJson(jsonDecode(jsonEncode(policy)));
}

String _decision(Json policy, String action) {
  final canonical = action == 'click' ? 'tap' : action;
  bool includes(String list) => (policy[list] as List? ?? []).any(
    (value) => (value == 'click' ? 'tap' : value) == canonical,
  );
  if (includes('deny')) return 'deny';
  if (includes('confirm')) return 'confirm';
  if (includes('allow')) return 'allow';
  return policy['default'] == 'deny' ||
          (policy['default'] == null &&
              (policy['allow'] as List?)?.isNotEmpty == true)
      ? 'deny'
      : 'allow';
}

Set<String> _actions(String command, Json params) {
  if (command == 'find') {
    return _actions((params['action'] ?? 'show') as String, params);
  }
  if (command == 'record' && !['start', 'restart'].contains(params['action'])) {
    return {};
  }
  if (command == 'clipboard' && params['action'] == 'read') return {};
  if (command == 'workflow') {
    final plan = WorkflowPlan.decode(
      params['workflow'],
      inputs: asJson(params['inputs']),
    );
    return {
      'workflow',
      for (final step in plan.steps) ..._actions(step.action, step.params),
    };
  }
  if (command == 'batch') {
    return {
      'batch',
      for (final step in validateBatch(params))
        ..._actions(step['command'] as String, asJson(step['params'])),
    };
  }
  return policyActions.contains(command) ? {command} : {};
}

class PendingAction {
  PendingAction(this.id, this.request, this.epoch)
    : expires = DateTime.now().add(const Duration(minutes: 5));
  final String id;
  final Request request;
  final int epoch;
  final DateTime expires;
}

/// Runs inside the session queue, before all UI delivery. Approvals are one-use.
Request authorizeRequest(Request request, Session session) {
  if (request.policy != null) {
    final next = validatePolicy(request.policy!);
    if (!const DeepCollectionEquality().equals(next, session.policy)) {
      session.policy = next;
      session.approval = null;
    }
  }
  if (request.command == 'confirm' || request.command == 'deny') {
    if (request.params.length != 1 || request.params['id'] is! String) {
      invalid('Specify one confirmation id');
    }
    final pending = session.approval;
    if (pending == null ||
        pending.id != request.params['id'] ||
        pending.epoch != session.epoch ||
        !pending.expires.isAfter(DateTime.now())) {
      throw const AgentError(
        'INVALID_ARGUMENT',
        'Confirmation is absent or expired',
      );
    }
    session.approval = null;
    if (request.command == 'deny') return request;
    return Request(
      requestId: request.requestId,
      session: request.session,
      command: pending.request.command,
      params: pending.request.params,
      deadline: request.deadline,
      maxOutput: request.maxOutput,
      outputJson: request.outputJson,
      debug: request.debug,
    );
  }
  final policy = session.policy;
  if (policy == null) return request;
  final decisions = _actions(
    request.command,
    request.params,
  ).map((action) => _decision(policy, action)).toSet();
  if (decisions.contains('deny')) {
    throw const AgentError(
      'ACTION_DENIED',
      'Action is denied by the session policy',
    );
  }
  if (decisions.contains('confirm')) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    session.approval = PendingAction(id, request, session.epoch);
    throw AgentError(
      'CONFIRMATION_REQUIRED',
      'Action requires confirmation',
      hint: 'Use confirm <id> or deny <id> in this session',
      details: {'confirmationId': id, 'command': request.command},
    );
  }
  return request;
}
