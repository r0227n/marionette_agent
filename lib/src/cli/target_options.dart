import 'package:args/args.dart';

import '../backend/backend.dart';
import '../commands/arguments.dart';
import '../snapshot/target.dart';

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
  return decodeTarget({
    'ref': ?ref,
    for (final kind in SelectorKind.values)
      if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
  });
}
