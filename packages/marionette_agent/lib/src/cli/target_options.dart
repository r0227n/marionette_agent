import 'package:args/args.dart';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/snapshot_service.dart';

/// Add shared selector options to individual command ArgParsers.
void addSelectorOptions(ArgParser parser) {
  for (final kind in SelectorKind.values) {
    parser.addOption(kind.name, help: 'Match exactly by ${kind.name}');
  }
}

/// Validate ref/selector exclusivity. Coordinate exclusivity is validated by the caller.
///
/// Caller extracts fill text and swipe direction from rest and passes them via [ref].
TargetQuery parseTarget(ArgResults args, {String? ref}) {
  final selected = SelectorKind.values
      .where((kind) => args.wasParsed(kind.name))
      .toList();
  if ((ref == null ? 0 : 1) + selected.length != 1) {
    invalid('Specify exactly one ref or selector');
  }
  if (ref != null) return RefQuery(ref);
  final kind = selected.single;
  final value = args.option(kind.name)!;
  if (value.isEmpty) invalid('Selector value must not be empty');
  return SelectorQuery(Selector(kind, value));
}
