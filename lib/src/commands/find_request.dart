import '../backend/backend.dart';
import '../protocol/protocol.dart';
import 'interaction_request.dart';

const findFields = [
  'key',
  'identifier',
  'text',
  'type',
  'role',
  'label',
  'placeholder',
];
const findPositions = ['first', 'last', 'nth'];

void validateFind(Json params) {
  final by = params['by'];
  final positional = findPositions.contains(by);
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
  if ((!findFields.contains(by) && !positional) ||
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
