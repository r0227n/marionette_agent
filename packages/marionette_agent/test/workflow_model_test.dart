import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/cli/workflow_loader.dart';
import 'package:marionette_agent/src/workflow/model.dart';
import 'package:marionette_agent/src/workflow/schema_catalog.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

Json doc([List<Json>? steps]) => {
  'schemaVersion': 1,
  'name': 'example',
  'steps':
      steps ??
      [
        {'id': 'last-step', 'action': 'snapshot'},
      ],
};
final invalidArg = throwsA(
  isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
);
void main() {
  test('bundled examples validate and JSON/YAML navigation is equivalent', () {
    final yaml = parseWorkflowText(
      File('examples/workflows/reach-controls.yaml').readAsStringSync(),
      'yaml',
    );
    final json = parseWorkflowText(
      File('examples/workflows/reach-controls.json').readAsStringSync(),
      'json',
    );
    expect(yaml, json);
    expect(WorkflowPlan.decode(json).steps.length, 6);
    final fill = parseWorkflowText(
      File('examples/workflows/fill-input.json').readAsStringSync(),
      'json',
    );
    final inputs = parseWorkflowText(
      File('examples/workflows/inputs.example.json').readAsStringSync(),
      'json',
    );
    expect(WorkflowPlan.decode(fill, inputs: inputs).steps.length, 2);
    expect(
      WorkflowPlan.decode(
        parseWorkflowText(
          File('examples/workflows/stop-on-missing.json').readAsStringSync(),
          'json',
        ),
      ).steps.length,
      3,
    );
  });
  test('JSON and safe YAML normalize equally including literal punctuation and BOM', () {
    const yaml = '''schemaVersion: 1
name: example
steps:
  - id: last-step
    action: snapshot
''';
    expect(
      parseWorkflowText('\uFEFF${jsonEncode(doc())}', 'json'),
      parseWorkflowText(yaml, 'yaml'),
    );
    expect(parseWorkflowText('text: "&anchor *alias !tag"', 'yaml'), {
      'text': '&anchor *alias !tag',
    });
    expect(parseWorkflowText('date: 2026-09-09', 'yaml'), {
      'date': '2026-09-09',
    });
  });
  for (final source in [
    'a: 1\na: 2',
    'a: &x hi',
    'a: *x',
    'a: !secret hi',
    'a: !!str hi',
    'a: {<<: {b: 1}}',
    '---\na: 1\n---\nb: 2',
    '1: value',
    '? [a,b]\n: c',
    'x: .nan',
    'x: .inf',
    '%YAML 1.1\n---\na: 1',
    '%UNKNOWN secret\n---\na: 1',
  ]) {
    test(
      'YAML rejects unsafe structure ${source.hashCode}',
      () => expect(() => parseWorkflowText(source, 'yaml'), invalidArg),
    );
  }
  test('JSON duplicate and escaped duplicate keys, trailing syntax, depth, nonfinite rejected', () {
    for (final s in [
      '{"a":1,"a":2}',
      r'{"a":1,"\u0061":2}',
      '{"a":1,}',
      '[1,]',
      '1e999',
      '${'[' * 33}0${']' * 33}',
    ]) {
      expect(() => parseWorkflowText(s, 'json'), invalidArg);
    }
    expect(
      () => parseWorkflowText('${'[' * 33}0${']' * 33}', 'yaml'),
      invalidArg,
    );
    expect(() => parseWorkflowText('', 'json'), invalidArg);
    expect(
      () => parseWorkflowText(' ' * (workflowFileLimit + 1), 'yaml'),
      invalidArg,
    );
  });
  test('closed fields, counts, IDs, references and actions', () {
    for (final value in [
      {...doc(), 'extra': true},
      {...doc(), 'schemaVersion': 1.0},
      doc([]),
      doc(List.generate(101, (i) => {'id': 's$i', 'action': 'snapshot'})),
      doc([
        {'id': 's', 'action': 'snapshot'},
        {'id': 's', 'action': 'snapshot'},
      ]),
      doc([
        {'id': 's', 'action': 'connect'},
      ]),
      doc([
        {'id': 's', 'action': 'workflow'},
      ]),
      doc([
        {
          'id': 's',
          'action': 'tap',
          'target': {'ref': '@e1'},
        },
      ]),
      doc([
        {
          'id': 's',
          'action': 'tap',
          'target': {'key': 'k', 'text': 'x'},
        },
      ]),
      doc([
        {
          'id': 's',
          'action': 'snapshot',
          'target': {'key': 'k'},
        },
      ]),
    ]) {
      expect(() => WorkflowPlan.decode(value), invalidArg);
    }
  });
  test(
    'template vs binding, defaults, required, optional unbound, empty strings',
    () {
      final d = {
        ...doc([
          {
            'id': 'fill',
            'action': 'fill',
            'target': {'key': 'field'},
            'text': {'input': 'name'},
          },
        ]),
        'inputs': {
          'name': {'type': 'string', 'required': true},
        },
      };
      expect(WorkflowPlan.decode(d, bind: false).requiredInputs, ['name']);
      expect(() => WorkflowPlan.decode(d), invalidArg);
      expect(
        WorkflowPlan.decode(
          d,
          inputs: {'name': ''},
        ).steps.single.params['input'],
        '',
      );
      for (final inputs in [
        {'name': null},
        {'name': 4},
        {'extra': 'x'},
      ]) {
        expect(() => WorkflowPlan.decode(d, inputs: inputs), invalidArg);
      }
      for (final def in [
        {'type': 'string', 'required': true, 'default': 'x'},
        {'type': 'string', 'sensitive': true, 'default': 'x'},
      ]) {
        expect(
          () => WorkflowPlan.decode({
            ...d,
            'inputs': {'name': def},
          }, bind: false),
          invalidArg,
        );
      }
      final optional = {
        ...d,
        'inputs': {
          'name': {'type': 'string'},
        },
      };
      expect(() => WorkflowPlan.decode(optional), invalidArg);
      expect(
        WorkflowPlan.decode({
          ...doc(),
          'inputs': {
            'name': {'type': 'string'},
          },
        }).steps.length,
        1,
      );
      expect(
        WorkflowPlan.decode({
          ...d,
          'inputs': {
            'name': {'type': 'string', 'default': 'default'},
          },
        }).steps.single.params['input'],
        'default',
      );
      expect(
        () => WorkflowPlan.decode({...d, 'inputs': {}}, bind: false),
        invalidArg,
      );
    },
  );
  test('scalar and byte limits preserve empty fill, unicode scalar count', () {
    expect(
      WorkflowPlan.decode({...doc(), 'description': '😀' * 256}).name,
      'example',
    );
    expect(
      () => WorkflowPlan.decode({...doc(), 'description': '😀' * 257}),
      invalidArg,
    );
    for (final value in [double.nan, double.infinity, 0, -1]) {
      expect(
        () => WorkflowPlan.decode(
          doc([
            {
              'id': 's',
              'action': 'swipe',
              'target': {'key': 'k'},
              'direction': 'left',
              'distance': value,
            },
          ]),
        ),
        invalidArg,
      );
    }
    for (final text in ['', 'x' * 65536]) {
      expect(
        WorkflowPlan.decode(
          doc([
            {
              'id': 's',
              'action': 'fill',
              'target': {'key': 'k'},
              'text': {'literal': text},
            },
          ]),
        ).steps.length,
        1,
      );
    }
    expect(
      () => WorkflowPlan.decode(
        doc([
          {
            'id': 's',
            'action': 'fill',
            'target': {'key': 'k'},
            'text': {'literal': '😀' * 16385},
          },
        ]),
      ),
      invalidArg,
    );
    for (final field in ['timeoutMs', 'pollIntervalMs']) {
      expect(
        () => WorkflowPlan.decode(
          doc([
            {
              'id': 's',
              'action': 'wait',
              'target': {'key': 'k'},
              'state': 'exists',
              field: 1.5,
            },
          ]),
        ),
        invalidArg,
      );
    }
  });
  test('each standalone schema resolves and agrees with the plan codec', () {
    for (final action in workflowActions) {
      final step = <String, Object?>{
        'id': 's',
        'action': action,
        if (action != 'snapshot') 'target': {'key': 'k'},
        if (action == 'fill') 'text': {'literal': ''},
        if (['swipe', 'scroll'].contains(action)) 'direction': 'left',
        if (action == 'wait') 'state': 'exists',
      };
      final schema = workflowSchema(action);
      validateSchema(step, schema, asJson(schema[r'$defs']));
      expect(WorkflowPlan.decode(doc([step])).steps.single.action, action);
      expect(
        () => validateSchema(
          {...step, 'extra': true},
          schema,
          asJson(schema[r'$defs']),
        ),
        invalidArg,
      );
      expect(
        () => WorkflowPlan.decode(
          doc([
            {...step, 'extra': true},
          ]),
        ),
        invalidArg,
      );
    }
    expect(
      jsonEncode(workflowSchema('tap')).length,
      lessThan(jsonEncode(workflowSchema()).length),
    );
    expect(() => workflowSchema('close'), invalidArg);
  });
  test('format inference and explicit override', () {
    expect(workflowFormat('a.yaml', 'json'), 'json');
    expect(workflowFormat('a.YML', null), 'yaml');
    expect(() => workflowFormat('-', null), invalidArg);
    expect(() => workflowFormat('file', null), invalidArg);
  });
}
