import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/snapshot_service.dart';

/// Shared target decoding for CLI grammar and daemon-side parameter validation.
TargetQuery decodeTarget(Json params) {
  final selected = SelectorKind.values
      .where((kind) => params.containsKey(kind.name))
      .toList();
  if ((params.containsKey('ref') ? 1 : 0) + selected.length != 1) {
    invalid('Specify exactly one ref or selector');
  }
  if (params.containsKey('ref')) {
    final ref = params['ref'];
    if (ref is! String) invalid('Expected a ref');
    return RefQuery(ref);
  }
  final kind = selected.single;
  final value = params[kind.name];
  if (value is! String || value.isEmpty) {
    invalid('Selector value must not be empty');
  }
  return SelectorQuery(Selector(kind, value));
}

double finiteNumber(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  if (number == null || !number.isFinite) invalid('Expected a finite number');
  return number;
}
