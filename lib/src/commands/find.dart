import '../backend/backend.dart';
import '../protocol/protocol.dart';
import 'actions.dart';
import 'command_context.dart';
import 'interactions.dart';

import 'find_request.dart';

export 'find_request.dart';

Future<Json> handleFind(CommandContext context, Json params) async {
  validateFind(params);
  final positional = findPositions.contains(params['by']);
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
  final target = await context.uniqueTarget(element);
  if (action == 'tap' || action == 'click') {
    return executeTap(context, ActionRequest(query: target));
  }
  if (action == 'fill') {
    return executeFill(
      context,
      ActionRequest(query: target, input: params['input'] as String),
    );
  }
  final interaction = InteractionRequest.parse(action as String, {
    ...target.selector.toJson(),
    if (params.containsKey('input')) 'input': params['input'],
  });
  return executeInteraction(
    context,
    InteractionRequest(action, target, interaction.arguments),
  );
}
