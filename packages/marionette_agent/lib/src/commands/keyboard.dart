import 'package:args/args.dart';

import '../backend/backend.dart';
import '../cli/parser.dart';
import '../protocol/protocol.dart';
import 'command_context.dart';
import 'interactions.dart';

CliCommand keyboardCommand() => CliCommand(
  ArgParser()
    ..addCommand('press')
    ..addCommand('type')
    ..addCommand('inserttext'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty || child == null || child.rest.length != 1) {
      invalid('Usage: keyboard press|type|inserttext <input>');
    }
    if (child.name == 'press') parseKey(child.rest.single);
    return {'action': child.name, 'input': child.rest.single};
  },
);

CliCommand clipboardCommand() => CliCommand(
  ArgParser()
    ..addCommand('read')
    ..addCommand('write')
    ..addCommand('copy')
    ..addCommand('paste'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty ||
        child == null ||
        child.rest.length != (child.name == 'write' ? 1 : 0)) {
      invalid('Usage: clipboard read|write <text>|copy|paste');
    }
    return {
      'action': child.name,
      if (child.name == 'write') 'input': child.rest.single,
    };
  },
);

Future<Json> handleKeyboard(CommandContext context, Json params) async {
  if (params.length != 2 ||
      params['input'] is! String ||
      !['press', 'type', 'inserttext'].contains(params['action'])) {
    invalid('Invalid keyboard arguments');
  }
  if (params['action'] == 'press') {
    return handleInteraction(context, 'press', {'input': params['input']});
  }
  await context.requireInteraction('keyboard.inserttext');
  return context.performCoordinates(
    (backend) => (backend as InteractionBackend).interact(
      'keyboard.inserttext',
      arguments: {'input': params['input']},
    ),
  );
}

Future<Json> handleClipboard(CommandContext context, Json params) async {
  final action = params['action'];
  if (!['read', 'write', 'copy', 'paste'].contains(action) ||
      params.length != (action == 'write' ? 2 : 1) ||
      (action == 'write' && params['input'] is! String) ||
      params.keys.any((key) => key != 'action' && key != 'input')) {
    invalid('Invalid clipboard arguments');
  }
  await context.requireInteraction('clipboard.$action');
  if (action == 'read') {
    final text = await context.read((backend) {
      if (backend is! ClipboardBackend) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Binding cannot read target clipboard',
        );
      }
      return (backend as ClipboardBackend).readClipboard();
    });
    return {'text': text, 'scope': 'target_app'};
  }
  Future<void> operation(Backend backend) =>
      (backend as InteractionBackend).interact(
        'clipboard.$action',
        arguments: {if (action == 'write') 'input': params['input']},
      );
  if (action == 'paste') return context.performCoordinates(operation);
  // copy/write change only the target clipboard, preserving observed UI refs.
  await context.performEffect(operation);
  return {'clipboard': action, 'scope': 'target_app'};
}
