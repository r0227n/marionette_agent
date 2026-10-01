import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../protocol/protocol.dart';

/// Explicit configuration only; file contents never become shell commands.
List<String> configArguments(
  ArgParser parser,
  ArgResults selected,
  Map<String, String> environment,
) {
  final path = selected.option('config');
  if (path == null) return [];
  try {
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file || stat.size > 1024 * 1024) {
      invalid('Config must be a regular JSON file of at most 1 MiB');
    }
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      invalid('Config must be a JSON object');
    }
    final result = <String>[];
    const excluded = {'config', 'help', 'version'};
    for (final entry in decoded.entries) {
      final name = entry.key as String;
      final option = parser.options[name];
      if (option == null || excluded.contains(name)) {
        invalid('Unknown config option');
      }
      final value = entry.value;
      if (option.isFlag ? value is! bool : value is! String && value is! int) {
        invalid('Invalid config option type');
      }
      if (selected.wasParsed(name) ||
          (name == 'session' &&
              environment.containsKey('MARIONETTE_AGENT_SESSION')) ||
          (name == 'timeout' &&
              environment.containsKey('MARIONETTE_AGENT_TIMEOUT_MS'))) {
        continue;
      }
      if (option.isFlag) {
        if (value == true) result.add('--$name');
      } else {
        result.add('--$name=$value');
      }
    }
    return result;
  } on AgentError {
    rethrow;
  } catch (_) {
    throw const AgentError(
      'INVALID_ARGUMENT',
      'Cannot read a valid JSON config',
    );
  }
}
