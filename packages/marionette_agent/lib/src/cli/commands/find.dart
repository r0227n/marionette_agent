import 'package:args/args.dart';

import '../../backend/backend.dart';
import '../../commands/find.dart';
import '../../protocol/protocol.dart';
import '../command.dart';
import '../target_options.dart';

CliCommand findCommand() {
  final parser = ArgParser();
  for (final name in [...findFields, ...findPositions]) {
    final child = ArgParser()
      ..addFlag('exact', negatable: false)
      ..addOption('name');
    if (findPositions.contains(name)) addSelectorOptions(child);
    parser.addCommand(name, child);
  }
  return CliCommand(parser, (args) {
    final child = args.command;
    if (child == null || args.rest.isNotEmpty) {
      invalid('Usage: find <attribute|first|last|nth> ...');
    }
    final rest = child.rest.toList();
    final params = <String, Object?>{
      'by': child.name,
      'exact': child.flag('exact'),
    };
    if (findFields.contains(child.name) || child.name == 'nth') {
      if (rest.isEmpty) invalid('Missing find value or index');
      params[child.name == 'nth' ? 'index' : 'value'] = child.name == 'nth'
          ? int.tryParse(rest.removeAt(0))
          : rest.removeAt(0);
    }
    if (findPositions.contains(child.name)) {
      for (final kind in SelectorKind.values) {
        if (child.wasParsed(kind.name)) {
          params[kind.name] = child.option(kind.name);
        }
      }
    }
    if (child.option('name') != null) params['name'] = child.option('name');
    if (rest.isNotEmpty) params['action'] = rest.removeAt(0);
    if (rest.isNotEmpty) params['input'] = rest.removeAt(0);
    if (rest.isNotEmpty) invalid('Unexpected find arguments');
    validateFind(params);
    return params;
  });
}
