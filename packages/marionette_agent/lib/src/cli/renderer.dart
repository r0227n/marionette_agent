import 'dart:convert';

import '../protocol/protocol.dart';

/// Render only normalized text/JSON results; do not interpret backend exceptions.
String render(Result result, {required bool json}) {
  if (json) return jsonEncode(result.toJson());
  final error = result.error;
  if (error != null) {
    final details = error.details;
    return [
      '${error.code}: ${error.message}',
      if (details != null) ...[
        if (details['progressKnown'] == true)
          'Workflow ${details['workflow'] ?? '-'}: ${details['completedSteps']} steps completed'
        else
          'Workflow progress unknown',
        if (details['stepIndex'] != null)
          'Failed step ${details['stepIndex']}: ${details['stepId']} (${details['action']})',
      ],
      'Outcome: ${error.toJson()['outcome']}',
      if (error.hint != null) error.hint!,
    ].join('\n');
  }
  final data = result.data!;
  if (data['help'] case final String help) return help;
  if (data['version'] case final String version) return version;
  if (data['completedSteps'] case final int count) {
    final snapshot = data['finalSnapshot'];
    return 'Workflow ${data['workflow']}: $count steps completed'
        '${snapshot == null ? '\nRun snapshot to inspect the current UI.' : '\n${render(Result.success(result.session, asJson(snapshot)), json: false)}'}';
  }
  if (data['elements'] case final List elements) {
    final lines = elements.map((value) {
      final element = asJson(value);
      return [
        element['ref'] ?? '-',
        element['type'],
        if (element['key'] != null) 'key=${jsonEncode(element['key'])}',
        if (element['identifier'] != null)
          'identifier=${jsonEncode(element['identifier'])}',
        if (element['text'] != null) jsonEncode(element['text']),
        if (element['reason'] != null) '(${element['reason']})',
      ].where((v) => v != null).join(' ');
    });
    return 'Snapshot ${data['generation']}\n${lines.join('\n')}';
  }
  return const JsonEncoder.withIndent('  ').convert(data);
}
