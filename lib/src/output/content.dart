import 'dart:convert';

import '../protocol/protocol.dart';

/// Shared item serialization keeps daemon budgets equal to rendered content.
String snapshotLine(Object? value) {
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
}

String contentItem(Object? item, String field, bool json) =>
    json || field == 'entries' ? jsonEncode(item) : snapshotLine(item);

/// Budget covers the serialized item sequence including separators, excluding
/// envelope, list brackets, trusted headings and boundary/count metadata.
Json limitContent(Json data, int? maximum, bool json) {
  if (maximum == null) return data;
  if (data['finalSnapshot'] case final Map snapshot) {
    return {
      ...data,
      'finalSnapshot': limitContent(asJson(snapshot), maximum, json),
    };
  }
  final field = data['elements'] is List
      ? 'elements'
      : data['entries'] is List
      ? 'entries'
      : null;
  if (field == null) return data;
  final items = data[field] as List;
  final selected = <Object?>[];
  var used = 0;
  for (final item in items) {
    final cost =
        contentItem(item, field, json).runes.length +
        (selected.isEmpty ? 0 : 1);
    if (cost > maximum - used) break;
    used += cost;
    selected.add(item);
  }
  return {
    ...data,
    field: selected,
    'truncated': selected.length < items.length,
    'originalCount': items.length,
    'omittedCount': items.length - selected.length,
  };
}
