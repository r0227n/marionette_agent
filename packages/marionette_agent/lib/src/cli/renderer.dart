import 'dart:convert';

import '../protocol/protocol.dart';

/// Render only normalized text/JSON results; do not interpret backend exceptions.
String render(Result result, {required bool json}) {
  if (json) return jsonEncode(result.toJson());
  final error = result.error;
  if (error != null) {
    return '${error.code}: ${error.message}\n${error.hint ?? ''}'.trimRight();
  }
  final data = result.data!;
  if (data['help'] case final String help) return help;
  if (data['version'] case final String version) return version;
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
