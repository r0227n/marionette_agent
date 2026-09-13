import 'package:args/args.dart';

import '../backend/backend.dart';
import '../cli/parser.dart';
import '../cli/target_options.dart';
import '../protocol/protocol.dart';
import '../snapshot/snapshot_service.dart';
import 'arguments.dart';
import 'command_context.dart';

const targetInteractions = [
  'dblclick',
  'type',
  'focus',
  'hover',
  'check',
  'uncheck',
  'select',
  'scrollintoview',
];
const keyboardInteractions = ['press', 'keydown', 'keyup'];

CliCommand interactionCommand(String action) {
  final parser = ArgParser();
  final keyboard = keyboardInteractions.contains(action);
  if (!keyboard) addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    final rest = args.rest.toList();
    final params = <String, Object?>{};
    if (keyboard) {
      if (rest.length != 1) invalid('Specify one key or key combination');
      params['input'] = rest.removeLast();
    } else {
      for (final kind in SelectorKind.values) {
        if (args.wasParsed(kind.name)) {
          params[kind.name] = args.option(kind.name);
        }
      }
      if (action == 'type' || action == 'select') {
        if (rest.isEmpty) invalid('A text or option value is required');
        params['input'] = rest.removeLast();
      }
      if (rest.length > 1) invalid('Specify one ref or selector');
      if (rest.isNotEmpty) params['ref'] = rest.single;
    }
    InteractionRequest.parse(action, params);
    return params;
  });
}

class InteractionRequest {
  InteractionRequest(this.action, this.target, this.arguments);
  final String action;
  final TargetQuery? target;
  final Json arguments;

  static InteractionRequest parse(String action, Json params) {
    final keyboard = keyboardInteractions.contains(action);
    final input = keyboard || action == 'type' || action == 'select';
    final allowed = {
      if (!keyboard) ...['ref', ...SelectorKind.values.map((k) => k.name)],
      if (input) 'input',
    };
    if ((!keyboard && !targetInteractions.contains(action)) ||
        params.keys.any((key) => !allowed.contains(key))) {
      invalid('Invalid interaction arguments');
    }
    if (input && params['input'] is! String) {
      invalid('Expected a text argument');
    }
    final arguments = <String, Object?>{};
    if (keyboard) {
      arguments.addAll(
        parseKey(params['input'] as String, chord: action == 'press'),
      );
    } else if (input) {
      arguments['input'] = params['input'];
    }
    return InteractionRequest(
      action,
      keyboard ? null : decodeTarget(params),
      arguments,
    );
  }
}

Json parseKey(String input, {bool chord = true}) {
  final aliases = {
    'ctrl': 'control',
    'cmd': 'meta',
    'command': 'meta',
    'option': 'alt',
    'esc': 'escape',
    'return': 'enter',
  };
  final parts = input
      .toLowerCase()
      .split('+')
      .map((part) => aliases[part] ?? part)
      .toList();
  final key = parts.removeLast();
  const modifiers = {'control', 'shift', 'alt', 'meta'};
  const named = {
    'enter',
    'tab',
    'escape',
    'backspace',
    'delete',
    'space',
    'arrowup',
    'arrowdown',
    'arrowleft',
    'arrowright',
    'home',
    'end',
    'pageup',
    'pagedown',
  };
  if ((!chord && parts.isNotEmpty) ||
      parts.toSet().length != parts.length ||
      parts.any((part) => !modifiers.contains(part)) ||
      (!named.contains(key) &&
          !RegExp(r'^[a-z0-9]$').hasMatch(key) &&
          !(modifiers.contains(key) && !chord))) {
    invalid('Unsupported key or modifier combination');
  }
  return {'key': key, 'modifiers': parts};
}

Future<Json> handleInteraction(
  CommandContext context,
  String action,
  Json params,
) async {
  final request = InteractionRequest.parse(action, params);
  await context.requireInteraction(action);
  if (request.target == null) {
    return context.performCoordinates(
      (backend) => (backend as InteractionBackend).interact(
        action,
        arguments: request.arguments,
      ),
    );
  }
  if (action == 'scrollintoview') {
    // Visibility is allowed to be false, but target uniqueness is still required.
    final resolved = await context.resolveRead(request.target!);
    return context.performCoordinates(
      (backend) => (backend as InteractionBackend).interact(
        action,
        target: resolved.selector,
        arguments: request.arguments,
      ),
    );
  }
  return context.performTarget(
    request.target!,
    (backend, selector) => (backend as InteractionBackend).interact(
      action,
      target: selector,
      arguments: request.arguments,
    ),
  );
}
