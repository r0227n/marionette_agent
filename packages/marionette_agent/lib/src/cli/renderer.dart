import 'dart:math';
import 'dart:convert';

import '../output/content.dart';
import '../protocol/protocol.dart';

/// Render only normalized text/JSON results; do not interpret backend exceptions.
String render(
  Result result, {
  required bool json,
  bool contentBoundaries = false,
}) {
  if (contentBoundaries && result.data != null) {
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    Json mark(Json data) {
      if (data['finalSnapshot'] case final Map snapshot) {
        return {...data, 'finalSnapshot': mark(asJson(snapshot))};
      }
      final source = data['elements'] is List
          ? 'snapshot'
          : data['entries'] is List
          ? 'logs'
          : null;
      return source == null
          ? data
          : {
              ...data,
              'contentBoundary': {'nonce': nonce, 'source': source},
            };
    }

    result = Result.success(result.session, mark(result.data!));
  }
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
  final field = data['elements'] is List
      ? 'elements'
      : data['entries'] is List
      ? 'entries'
      : null;
  if (field != null) {
    final items = data[field] as List;
    final boundary = data['contentBoundary'] as Map?;
    final source = field == 'elements' ? 'snapshot' : 'logs';
    return [
      field == 'elements' ? 'Snapshot ${data['generation']}' : 'Logs',
      if (field == 'entries' && data['configured'] != null)
        'Configured: ${data['configured']}',
      if (field == 'entries' && data['limitation'] != null)
        '${data['limitation']}',
      if (boundary != null)
        '--- BEGIN UNTRUSTED $source ${boundary['nonce']} ---',
      ...items.map((item) => contentItem(item, field, false)),
      if (boundary != null)
        '--- END UNTRUSTED $source ${boundary['nonce']} ---',
      if (data.containsKey('truncated'))
        'Truncated: ${data['truncated']}; originalCount: ${data['originalCount']}; omittedCount: ${data['omittedCount']}',
    ].join('\n');
  }
  return const JsonEncoder.withIndent('  ').convert(data);
}
