import 'dart:convert';

import '../protocol/protocol.dart';
import '../session/action_policy.dart';
import 'common_options.dart';
import 'input_file.dart';

Future<Json?> loadPolicy(CommonOptions options, DateTime deadline) async {
  if (options.actionPolicy == null && options.confirmActions == null) {
    return null;
  }
  Json policy = {};
  if (options.actionPolicy != null) {
    try {
      policy = asJson(
        jsonDecode(
          utf8.decode(await readInputFile(options.actionPolicy!, deadline)),
        ),
      );
    } on AgentError {
      rethrow;
    } catch (_) {
      invalid('Invalid JSON action policy');
    }
  }
  if (options.confirmActions != null) {
    final actions = options.confirmActions!
        .split(',')
        .map((action) => action.trim())
        .toList();
    final previous = policy['confirm'];
    if (previous != null && previous is! List) {
      invalid('Invalid confirmation policy');
    }
    policy['confirm'] = {...?previous as List?, ...actions}.toList();
  }
  return validatePolicy(policy);
}
