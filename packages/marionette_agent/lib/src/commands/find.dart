import 'package:args/args.dart';

import '../backend/backend.dart';
import '../cli/parser.dart';
import '../cli/target_options.dart';
import '../protocol/protocol.dart';
import 'actions.dart';
import 'command_context.dart';
import 'interactions.dart';

const _fields = [
  'key',
  'identifier',
  'text',
  'type',
  'role',
  'label',
  'placeholder',
];
const _positions = ['first', 'last', 'nth'];

CliCommand findCommand() {
  final parser = ArgParser();
  for (final name in [..._fields, ..._positions]) {
    final child = ArgParser()
      ..addFlag('exact', negatable: false)
      ..addOption('name');
    if (_positions.contains(name)) addSelectorOptions(child);
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
    if (_fields.contains(child.name) || child.name == 'nth') {
      if (rest.isEmpty) invalid('Missing find value or index');
      params[child.name == 'nth' ? 'index' : 'value'] = child.name == 'nth'
          ? int.tryParse(rest.removeAt(0))
          : rest.removeAt(0);
    }
    if (_positions.contains(child.name)) {
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
    _validate(params);
    return params;
  });
}

void _validate(Json params) {
  final by = params['by'];
  final positional = _positions.contains(by);
  final allowed = {
    'by',
    'exact',
    'action',
    'input',
    'name',
    if (positional) ...SelectorKind.values.map((k) => k.name),
    if (by == 'nth') 'index',
    if (!positional) 'value',
  };
  if ((!_fields.contains(by) && !positional) ||
      params.keys.any((key) => !allowed.contains(key)) ||
      params['exact'] is! bool) {
    invalid('Invalid find arguments');
  }
  if (!positional &&
      (params['value'] is! String || (params['value'] as String).isEmpty)) {
    invalid('Find value must not be empty');
  }
  if (by == 'nth' &&
      (params['index'] is! int || (params['index'] as int) < 0)) {
    invalid('Find index must be a non-negative integer (zero-based)');
  }
  if (positional) {
    final kinds = SelectorKind.values
        .where((kind) => params.containsKey(kind.name))
        .toList();
    if (kinds.length != 1 ||
        params[kinds.single.name] is! String ||
        (params[kinds.single.name] as String).isEmpty) {
      invalid('Positional find requires one selector');
    }
  }
  if (params.containsKey('name') &&
      (by != 'role' ||
          params['name'] is! String ||
          (params['name'] as String).isEmpty)) {
    invalid('--name requires role and a non-empty name');
  }
  final action = params['action'] ?? 'show';
  if (![
    'show',
    'tap',
    'click',
    'fill',
    ...targetInteractions,
  ].contains(action)) {
    invalid('Unsupported find action');
  }
  if (['fill', 'type', 'select'].contains(action)) {
    if (params['input'] is! String) invalid('Find action requires input');
  } else if (params.containsKey('input')) {
    invalid('Unexpected find input');
  }
}

Future<Json> handleFind(CommandContext context, Json params) async {
  _validate(params);
  final positional = _positions.contains(params['by']);
  final field = positional
      ? SelectorKind.values
            .firstWhere((kind) => params.containsKey(kind.name))
            .name
      : params['by'] as String;
  final value = (positional ? params[field] : params['value']) as String;
  final exact =
      params['exact'] == true ||
      positional ||
      field == 'role' ||
      field == 'key' ||
      field == 'identifier';
  bool matches(Object? observed, String expected, bool exact) =>
      observed is String &&
      (exact ? observed == expected : observed.contains(expected));
  final elements = await context.read((backend) => backend.inspect());
  final matchesList = elements.where((element) {
    final row = element.toJson();
    return matches(row[field], value, exact) &&
        (!params.containsKey('name') ||
            matches(
              row['label'],
              params['name'] as String,
              params['exact'] == true,
            ));
  }).toList();
  context.check();
  if (matchesList.isEmpty) {
    throw const AgentError('TARGET_NOT_FOUND', 'No element matches');
  }
  if (!positional && matchesList.length > 1) {
    throw const AgentError('AMBIGUOUS_TARGET', 'Multiple elements match');
  }
  final index = params['by'] == 'last'
      ? matchesList.length - 1
      : params['by'] == 'nth'
      ? params['index'] as int
      : 0;
  if (index >= matchesList.length) {
    throw const AgentError(
      'TARGET_NOT_FOUND',
      'Find index is outside the matching elements',
    );
  }
  final element = matchesList[index];
  final action = params['action'] ?? 'show';
  if (action == 'show') {
    return {
      'element': element.toJson(),
      'index': index,
      'matchedCount': matchesList.length,
    };
  }
  final selector = await context.uniqueSelector(element);
  final target = {
    ...selector.toJson(),
    if (params.containsKey('input')) 'input': params['input'],
  };
  if (action == 'tap' || action == 'click') return handleTap(context, target);
  if (action == 'fill') return handleFill(context, target);
  return handleInteraction(context, action as String, target);
}
