import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';

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
