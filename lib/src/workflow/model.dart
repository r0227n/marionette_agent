import 'dart:convert';

import '../backend/backend.dart';
import '../commands/wait_request.dart';
import '../protocol/protocol.dart';
import 'schema_catalog.dart';

const workflowFileLimit = 1024 * 1024;
const workflowTextLimit = 64 * 1024;

/// Validate the closed, bundled schema subset. Semantic constraints follow below.
void validateSchema(Object? value, Json schema, Json defs) {
  if (schema[r'$ref'] case final String ref) {
    validateSchema(value, asJson(defs[ref.split('/').last]), defs);
    return;
  }
  if (schema['oneOf'] case final List choices) {
    var matches = 0;
    for (final choice in choices) {
      try {
        validateSchema(value, asJson(choice), defs);
        matches++;
      } on AgentError {
        /* Try each exclusive shape without echoing values. */
      }
    }
    if (matches != 1) invalid('Invalid workflow shape');
  }
  if (schema.containsKey('const') && value != schema['const']) invalid();
  if (schema['enum'] case final List values) {
    if (!values.contains(value)) invalid();
  }
  final type = schema['type'];
  if (type != null &&
      !switch (type) {
        'object' => value is Map<String, Object?>,
        'array' => value is List,
        'string' => value is String,
        'boolean' => value is bool,
        'integer' => value is int,
        'number' => value is num && value.isFinite,
        _ => false,
      }) {
    invalid('Invalid workflow type');
  }
  if (value is Map<String, Object?>) {
    final props = asJson(schema['properties'] ?? <String, Object?>{});
    for (final key in (schema['required'] as List? ?? [])) {
      if (!value.containsKey(key)) invalid('Missing workflow field');
    }
    if (schema['maxProperties'] case final int max) {
      if (value.length > max) invalid();
    }
    for (final entry in value.entries) {
      if (schema['propertyNames'] case final Map names) {
        validateSchema(entry.key, asJson(names), defs);
      }
      final child = props[entry.key] ?? schema['additionalProperties'];
      if (child == false) invalid('Unknown workflow field');
      if (child is Map) validateSchema(entry.value, asJson(child), defs);
    }
  }
  if (value is List) {
    if (value.length < (schema['minItems'] as int? ?? 0) ||
        value.length > (schema['maxItems'] as int? ?? 0x7fffffff)) {
      invalid();
    }
    if (schema['items'] case final Map child) {
      for (final item in value) {
        validateSchema(item, asJson(child), defs);
      }
    }
  }
  if (value is String) {
    if (value.runes.length < (schema['minLength'] as int? ?? 0) ||
        value.runes.length > (schema['maxLength'] as int? ?? 0x7fffffff)) {
      invalid();
    }
    if (schema['pattern'] case final String pattern) {
      if (!RegExp(pattern).hasMatch(value)) invalid();
    }
  }
  if (value is num) {
    if (!value.isFinite) invalid();
    if (schema['minimum'] case final num min) {
      if (value < min) invalid();
    }
    if (schema['maximum'] case final num max) {
      if (value > max) invalid();
    }
    if (schema['exclusiveMinimum'] case final num min) {
      if (value <= min) invalid();
    }
  }
}

void checkTree(Object? value, [int depth = 0]) {
  if (value is Map || value is List) {
    if (depth >= 32) invalid('Workflow nesting limit exceeded');
    if (value is Map) {
      for (final e in value.entries) {
        if (e.key is! String) invalid();
        checkTree(e.value, depth + 1);
      }
    } else {
      for (final item in value as List) {
        checkTree(item, depth + 1);
      }
    }
  } else if (value is num && !value.isFinite) {
    invalid();
  } else if (value != null &&
      value is! String &&
      value is! bool &&
      value is! num) {
    invalid();
  }
}

void checkBytes(Object? value, int limit) {
  if (utf8.encode(jsonEncode(value)).length > limit) {
    invalid('Workflow size limit exceeded');
  }
}

void checkText(String value) {
  if (utf8.encode(value).length > workflowTextLimit) {
    invalid('Workflow text limit exceeded');
  }
}

class WorkflowStep {
  WorkflowStep(
    this.id,
    this.action,
    this.params, {
    this.selector,
    this.state,
    this.timeoutMs = 5000,
    this.pollIntervalMs = defaultWaitPollIntervalMs,
  });
  final String id, action;
  final Json params;
  final Selector? selector;
  final String? state;
  final int timeoutMs, pollIntervalMs;
}

/// Fully validate every step before creating an executable plan.
class WorkflowPlan {
  WorkflowPlan._(this.name, this.steps, this.requiredInputs);
  final String name;
  final List<WorkflowStep> steps;
  final List<String> requiredInputs;
  static WorkflowPlan decode(
    Object? document, {
    Object? inputs = const <String, Object?>{},
    bool bind = true,
  }) {
    checkTree(document);
    checkTree(inputs);
    checkBytes(document, workflowFileLimit);
    checkBytes(inputs, workflowFileLimit);
    final schema = workflowSchema();
    validateSchema(document, schema, asJson(schema[r'$defs']));
    final doc = asJson(document);
    if (inputs is! Map<String, Object?>) invalid('Inputs must be an object');
    final definitions = asJson(doc['inputs'] ?? <String, Object?>{});
    final values = <String, String>{};
    for (final entry in inputs.entries) {
      if (!definitions.containsKey(entry.key) || entry.value is! String) {
        invalid('Invalid input binding');
      }
      checkText(entry.value as String);
      values[entry.key] = entry.value as String;
    }
    final needed = <String>{};
    for (final entry in definitions.entries) {
      final def = asJson(entry.value);
      if (def.containsKey('default')) {
        if (def['required'] == true || def['sensitive'] == true) {
          invalid('Input default is forbidden');
        }
        checkText(def['default'] as String);
        values.putIfAbsent(entry.key, () => def['default'] as String);
      }
      if (def['required'] == true) needed.add(entry.key);
    }
    final ids = <String>{};
    final steps = <WorkflowStep>[];
    for (final value in doc['steps'] as List) {
      final step = asJson(value);
      final id = step['id'] as String;
      final action = step['action'] as String;
      if (!ids.add(id)) invalid('Duplicate step ID');
      final target = asJson(step['target'] ?? <String, Object?>{});
      final selector = target.isEmpty
          ? null
          : Selector(
              SelectorKind.values.byName(target.keys.single),
              target.values.single as String,
            );
      final params = <String, Object?>{...target};
      if (action == 'fill') {
        final text = asJson(step['text']);
        if (text.containsKey('literal')) {
          checkText(text['literal'] as String);
          params['input'] = text['literal'];
        } else {
          final key = text['input'] as String;
          if (!definitions.containsKey(key)) {
            invalid('Undeclared input reference');
          }
          if (!asJson(definitions[key]).containsKey('default')) needed.add(key);
          params['input'] = values[key];
        }
      }
      if (action == 'swipe' || action == 'scroll') {
        params['direction'] = step['direction'];
        params['distance'] = step['distance'] ?? 200;
      }
      if (action == 'wait') {
        params['state'] = step['state'];
        params['pollIntervalMs'] =
            step['pollIntervalMs'] ?? defaultWaitPollIntervalMs;
      }
      steps.add(
        WorkflowStep(
          id,
          action,
          params,
          selector: selector,
          state: step['state'] as String?,
          timeoutMs: step['timeoutMs'] as int? ?? 5000,
          pollIntervalMs:
              step['pollIntervalMs'] as int? ?? defaultWaitPollIntervalMs,
        ),
      );
    }
    if (bind && needed.any((key) => !inputs.containsKey(key))) {
      invalid('Required input is missing');
    }
    checkBytes({'workflow': doc, 'inputs': inputs}, 8 * 1024 * 1024);
    checkBytes([for (final step in steps) step.params], 8 * 1024 * 1024);
    return WorkflowPlan._(
      doc['name'] as String,
      steps,
      needed.toList()..sort(),
    );
  }
}

AgentError workflowError(
  AgentError error, {
  String? name,
  bool known = true,
  int? completed = 0,
  int? index,
  WorkflowStep? step,
}) => AgentError(
  error.code,
  index == null ? error.message : 'Workflow step failed',
  hint: 'Inspect the current UI; completed steps must not be replayed automatically',
  outcome: error.outcome,
  details: {
    'workflow': ?name,
    'progressKnown': known,
    'stepIndex': known ? index : null,
    'stepId': known ? step?.id : null,
    'action': known ? step?.action : null,
    'completedSteps': known ? completed : null,
  },
);

/// Only validated identifiers may appear in execution reports, never raw input.
String? workflowNameFrom(Object? document) {
  if (document is Map && document['name'] is String) {
    final name = document['name'] as String;
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(name)) return name;
  }
  return null;
}
