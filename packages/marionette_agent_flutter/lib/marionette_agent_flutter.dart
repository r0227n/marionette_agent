import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// Optional typed Widget observations. No extensions are registered in release.
/// Call after MarionetteBinding.ensureInitialized and before runApp.
void registerAgentExtensions() {
  if (!kDebugMode) return;
  final provider = AgentExtensionProvider();
  registerMarionetteExtension(
    name: 'marionette_agent.inspect',
    callback: (_) async =>
        MarionetteExtensionResult.success(provider.inspect()),
  );
  registerMarionetteExtension(
    name: 'marionette_agent.interact',
    callback: (params) async {
      try {
        final request =
            jsonDecode(params['request'] ?? '') as Map<String, dynamic>;
        return MarionetteExtensionResult.success(
          await provider.interact(request),
        );
      } on AgentExtensionFailure catch (error) {
        return MarionetteExtensionResult.success({'errorCode': error.code});
      } catch (_) {
        return const MarionetteExtensionResult.success({
          'errorCode': 'BACKEND_ERROR',
        });
      }
    },
  );
}

class AgentExtensionFailure implements Exception {
  const AgentExtensionFailure(this.code);
  final String code;
}

/// Uses public typed Widget/State APIs, never diagnostic strings or guessed roles.
/// Inspection covers mounted widgets, including mounted offscreen children, but
/// cannot materialize lazy list items. Selectors are re-matched at action time.
class AgentExtensionProvider {
  static const interactions = [
    'type',
    'focus',
    'hover',
    'drag',
    'check',
    'uncheck',
    'select',
    'scrollintoview',
    'keydown',
    'keyup',
    'keyboard.inserttext',
    'keyboard.release',
    'clipboard.read',
    'clipboard.write',
    'clipboard.copy',
    'clipboard.paste',
  ];
  final _held = <String>{};
  int _timestamp = 0;

  Map<String, Object?> inspect() => {
    'version': 1,
    'interactions': interactions,
    'elements': [for (final entry in _entries()) entry.data],
  };

  List<_Entry> _entries() {
    final entries = <_Entry>[];
    void visit(Element element, int depth) {
      final widget = element.widget;
      final data = _describe(element, depth);
      if (data != null) entries.add(_Entry(element, data));
      if (widget is Offstage && widget.offstage) return;
      element.visitChildren(
        (child) => visit(child, depth + (data == null ? 0 : 1)),
      );
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root, 0);
    return entries;
  }

  Map<String, Object?>? _describe(Element element, int depth) {
    final widget = element.widget;
    final key = widget.key is ValueKey<String>
        ? (widget.key as ValueKey<String>).value
        : null;
    final relevant =
        key != null ||
        widget is Text ||
        widget is RichText ||
        widget is Semantics ||
        widget is ButtonStyleButton ||
        widget is TextField ||
        widget is EditableText ||
        widget is Checkbox ||
        widget is Switch ||
        widget is DropdownButton ||
        widget is GestureDetector ||
        widget is MouseRegion ||
        widget is Focus;
    if (!relevant) return null;
    String? text, input, role, label, placeholder;
    bool? enabled, checked;
    var interactive = false;
    if (widget is Text) text = widget.data ?? widget.textSpan?.toPlainText();
    if (widget is RichText) text = widget.text.toPlainText();
    if (widget is Semantics) {
      final properties = widget.properties;
      label = properties.label;
      enabled = properties.enabled;
      checked = properties.mixed == true ? null : properties.checked;
      // Only explicit semantic flags provide a semantic role.
      role = properties.button == true
          ? 'button'
          : properties.textField == true
          ? 'textbox'
          : properties.link == true
          ? 'link'
          : properties.header == true
          ? 'heading'
          : null;
      interactive =
          properties.onTap != null ||
          properties.onSetText != null ||
          properties.onLongPress != null ||
          properties.focused != null;
    }
    if (widget is ButtonStyleButton) {
      enabled = widget.enabled;
      interactive = true;
    }
    if (widget is TextField || widget is EditableText) {
      final editable = _editable(element);
      if (editable != null) {
        input = editable.widget.obscureText
            ? null
            : editable.widget.controller.text;
        text = input;
      }
      if (widget is TextField) {
        enabled = widget.enabled ?? widget.decoration?.enabled ?? true;
        label = widget.decoration?.labelText;
        placeholder = widget.decoration?.hintText;
      }
      // EditableText has no enabled flag. readOnly does not imply disabled.
      interactive = true;
    }
    if (widget is Checkbox) {
      checked = widget.value;
      enabled = widget.onChanged != null;
      interactive = true;
    }
    if (widget is Switch) {
      checked = widget.value;
      enabled = widget.onChanged != null;
      interactive = true;
    }
    if (widget is DropdownButton<String>) {
      enabled = widget.onChanged != null && widget.items?.isNotEmpty == true;
      interactive = true;
    }
    if (widget is GestureDetector) {
      interactive =
          widget.onTap != null ||
          widget.onDoubleTap != null ||
          widget.onLongPress != null ||
          widget.onPanUpdate != null;
    }
    if (widget is MouseRegion) {
      interactive = widget.onHover != null || widget.onEnter != null;
    }
    if (widget is Focus) interactive = widget.canRequestFocus;
    final box = element.findRenderObject();
    Map<String, double>? bounds;
    bool? visible;
    if (box is RenderBox && box.attached && box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      final size = box.size;
      if (origin.dx.isFinite &&
          origin.dy.isFinite &&
          size.width.isFinite &&
          size.height.isFinite) {
        bounds = {
          'x': origin.dx,
          'y': origin.dy,
          'width': size.width,
          'height': size.height,
        };
        final view = View.maybeOf(element);
        if (view != null) {
          final rect = origin & size;
          visible =
              !size.isEmpty &&
              rect.overlaps(
                Offset.zero & (view.physicalSize / view.devicePixelRatio),
              );
          if (visible == true) {
            final hits = HitTestResult();
            WidgetsBinding.instance.hitTestInView(
              hits,
              rect.center,
              view.viewId,
            );
            visible = hits.path.any((entry) => identical(entry.target, box));
          }
          element.visitAncestorElements((ancestor) {
            final w = ancestor.widget;
            if (w is Offstage && w.offstage) visible = false;
            return visible != false;
          });
        }
      }
    }
    return {
      'type': widget.runtimeType.toString(),
      'depth': depth,
      'interactive': interactive,
      'key': ?key,
      'text': ?text,
      'inputValue': ?input,
      'enabled': ?enabled,
      'checked': ?checked,
      'role': ?role,
      'label': ?label,
      'placeholder': ?placeholder,
      'bounds': ?bounds,
      'visible': ?visible,
    };
  }

  EditableTextState? _editable(Element root) {
    final found = <EditableTextState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        found.add(element.state as EditableTextState);
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found.length == 1 ? found.single : null;
  }

  _Entry _target(Object? raw) {
    if (raw is! Map || raw.length != 1) {
      throw const AgentExtensionFailure('INVALID_ARGUMENT');
    }
    final kind = raw.keys.single;
    final value = raw.values.single;
    if (!['key', 'text', 'type'].contains(kind) ||
        value is! String ||
        value.isEmpty) {
      throw const AgentExtensionFailure('INVALID_ARGUMENT');
    }
    final matches = _entries()
        .where((entry) => entry.data[kind] == value)
        .toList();
    if (matches.isEmpty) throw const AgentExtensionFailure('TARGET_NOT_FOUND');
    if (matches.length != 1) {
      throw const AgentExtensionFailure('AMBIGUOUS_TARGET');
    }
    return matches.single;
  }

  Future<Map<String, Object?>> interact(Map<String, dynamic> request) async {
    final action = request['action'];
    if (!interactions.contains(action)) {
      throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
    }
    if (request.keys.any(
      (key) => !['action', 'target', 'arguments'].contains(key),
    )) {
      throw const AgentExtensionFailure('INVALID_ARGUMENT');
    }
    final args = request['arguments'];
    if (args is! Map) throw const AgentExtensionFailure('INVALID_ARGUMENT');
    final fields = switch (action) {
      'type' ||
      'select' ||
      'keyboard.inserttext' ||
      'clipboard.write' => {'input'},
      'keydown' || 'keyup' => {'key', 'modifiers'},
      'drag' => {'destination'},
      _ => <String>{},
    };
    if (args.keys.any((key) => !fields.contains(key)) ||
        (fields.contains('input') && args['input'] is! String)) {
      throw const AgentExtensionFailure('INVALID_ARGUMENT');
    }
    if (action == 'keyboard.release') {
      for (final key in _held.toList().reversed) {
        _key(key, false);
      }
      return {};
    }
    if (action == 'keydown' || action == 'keyup') {
      final key = args['key'];
      if (key is! String) throw const AgentExtensionFailure('INVALID_ARGUMENT');
      _key(key, action == 'keydown');
      return {};
    }
    if (action == 'clipboard.read') {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      return {'text': value?.text};
    }
    if (action == 'clipboard.write') {
      if (args['input'] is! String) {
        throw const AgentExtensionFailure('INVALID_ARGUMENT');
      }
      await Clipboard.setData(ClipboardData(text: args['input'] as String));
      return {};
    }
    if (action == 'clipboard.copy' ||
        action == 'clipboard.paste' ||
        action == 'keyboard.inserttext') {
      final context = FocusManager.instance.primaryFocus?.context;
      final editable = context is Element
          ? context.findAncestorStateOfType<EditableTextState>() ??
                _editable(context)
          : null;
      if (editable == null) {
        throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
      }
      if (action == 'clipboard.copy') {
        if (editable.widget.obscureText) {
          throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
        }
        final value = editable.widget.controller.value;
        if (!value.selection.isValid) {
          throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
        }
        await Clipboard.setData(
          ClipboardData(text: value.selection.textInside(value.text)),
        );
      } else {
        final text = action == 'clipboard.paste'
            ? (await Clipboard.getData(Clipboard.kTextPlain))?.text
            : args['input'];
        if (text is! String) {
          throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
        }
        _insert(editable, text);
      }
      return {};
    }
    final entry = _target(request['target']);
    final element = entry.element;
    if (action != 'scrollintoview' && entry.data['visible'] == false) {
      throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
    }
    if (entry.data['enabled'] == false) {
      throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
    }
    switch (action) {
      case 'type':
      case 'focus':
        final editable = _editable(element);
        if (editable != null) {
          if (action == 'type' && editable.widget.readOnly) {
            throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
          }
          if (!editable.widget.focusNode.canRequestFocus) {
            throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
          }
          editable.widget.focusNode.requestFocus();
          if (action == 'type') {
            if (args['input'] is! String) {
              throw const AgentExtensionFailure('INVALID_ARGUMENT');
            }
            _insert(editable, args['input'] as String);
          }
        } else if (action == 'focus' && element.widget is Focus) {
          final node = (element.widget as Focus).focusNode;
          if (node == null || !node.canRequestFocus) {
            throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
          }
          node.requestFocus();
        } else {
          throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
        }
      case 'scrollintoview':
        await Scrollable.ensureVisible(
          element,
          duration: const Duration(milliseconds: 250),
        );
      case 'check':
      case 'uncheck':
        final desired = action == 'check';
        final widget = element.widget;
        if (widget is Checkbox && widget.onChanged != null) {
          if (widget.value != desired) widget.onChanged!(desired);
        } else if (widget is Switch && widget.onChanged != null) {
          if (widget.value != desired) widget.onChanged!(desired);
        } else {
          throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
        }
      case 'select':
        final widget = element.widget;
        final input = args['input'];
        if (widget is! DropdownButton<String> ||
            widget.onChanged == null ||
            input is! String) {
          throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
        }
        final items =
            widget.items
                ?.where((item) => item.value == input && item.enabled)
                .toList() ??
            [];
        if (items.length != 1) {
          throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
        }
        if (widget.value != input) widget.onChanged!(input);
      case 'drag':
        final end = _target(args['destination']);
        final from = element.findRenderObject(),
            to = end.element.findRenderObject();
        final view = View.maybeOf(element);
        if (from is! RenderBox ||
            to is! RenderBox ||
            !from.hasSize ||
            !to.hasSize ||
            view == null ||
            end.data['visible'] == false ||
            View.maybeOf(end.element)?.viewId != view.viewId) {
          throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
        }
        final start = from.localToGlobal(from.size.center(Offset.zero));
        final finish = to.localToGlobal(to.size.center(Offset.zero));
        if (start == finish) {
          throw const AgentExtensionFailure('INVALID_ARGUMENT');
        }
        const pointer = 899997;
        final binding = GestureBinding.instance;
        binding.handlePointerEvent(
          PointerDownEvent(
            pointer: pointer,
            position: start,
            viewId: view.viewId,
          ),
        );
        var released = false;
        try {
          var previous = start;
          for (var step = 1; step <= 15; step++) {
            final position = Offset.lerp(start, finish, step / 15)!;
            binding.handlePointerEvent(
              PointerMoveEvent(
                pointer: pointer,
                position: position,
                delta: position - previous,
                viewId: view.viewId,
              ),
            );
            previous = position;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          binding.handlePointerEvent(
            PointerUpEvent(
              pointer: pointer,
              position: finish,
              viewId: view.viewId,
            ),
          );
          released = true;
        } finally {
          if (!released) {
            binding.handlePointerEvent(
              PointerCancelEvent(pointer: pointer, viewId: view.viewId),
            );
          }
        }
      case 'hover':
        final bounds = entry.data['bounds'] as Map?;
        final view = View.maybeOf(element);
        if (bounds == null || view == null) {
          throw const AgentExtensionFailure('UNSUPPORTED_CAPABILITY');
        }
        final position = Offset(
          (bounds['x'] as num).toDouble() +
              (bounds['width'] as num).toDouble() / 2,
          (bounds['y'] as num).toDouble() +
              (bounds['height'] as num).toDouble() / 2,
        );
        GestureBinding.instance.handlePointerEvent(
          PointerAddedEvent(
            device: 899998,
            kind: PointerDeviceKind.mouse,
            viewId: view.viewId,
          ),
        );
        GestureBinding.instance.handlePointerEvent(
          PointerHoverEvent(
            device: 899998,
            position: position,
            kind: PointerDeviceKind.mouse,
            viewId: view.viewId,
          ),
        );
        GestureBinding.instance.handlePointerEvent(
          PointerRemovedEvent(
            device: 899998,
            kind: PointerDeviceKind.mouse,
            viewId: view.viewId,
          ),
        );
    }
    WidgetsBinding.instance.scheduleFrame();
    return {};
  }

  void _insert(EditableTextState editable, String text) {
    if (editable.widget.readOnly) {
      throw const AgentExtensionFailure('UNRESOLVABLE_TARGET');
    }
    final value = editable.widget.controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final updated = value.text.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    editable.userUpdateTextEditingValue(
      TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      ),
      SelectionChangedCause.keyboard,
    );
  }

  void _key(String name, bool down) {
    final pair = _keys[name];
    if (pair == null) throw const AgentExtensionFailure('INVALID_ARGUMENT');
    if (down ? _held.contains(name) : !_held.contains(name)) {
      throw const AgentExtensionFailure('INVALID_ARGUMENT');
    }
    final event = down
        ? KeyDownEvent(
            physicalKey: pair.$1,
            logicalKey: pair.$2,
            timeStamp: Duration(microseconds: _timestamp++),
          )
        : KeyUpEvent(
            physicalKey: pair.$1,
            logicalKey: pair.$2,
            timeStamp: Duration(microseconds: _timestamp++),
          );
    if (down) {
      _held.add(name);
    } else {
      _held.remove(name);
    }
    HardwareKeyboard.instance.handleKeyEvent(event);
    // Flutter currently routes injected events into Focus through this handler.
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
      // ignore: deprecated_member_use
      KeyMessage([event], null),
    );
    WidgetsBinding.instance.scheduleFrame();
  }
}

class _Entry {
  const _Entry(this.element, this.data);
  final Element element;
  final Map<String, Object?> data;
}

final _keys = <String, (PhysicalKeyboardKey, LogicalKeyboardKey)>{
  'enter': (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter),
  'tab': (PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab),
  'escape': (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape),
  'backspace': (PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace),
  'delete': (PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete),
  'space': (PhysicalKeyboardKey.space, LogicalKeyboardKey.space),
  'arrowup': (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp),
  'arrowdown': (PhysicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown),
  'arrowleft': (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft),
  'arrowright': (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight),
  'home': (PhysicalKeyboardKey.home, LogicalKeyboardKey.home),
  'end': (PhysicalKeyboardKey.end, LogicalKeyboardKey.end),
  'pageup': (PhysicalKeyboardKey.pageUp, LogicalKeyboardKey.pageUp),
  'pagedown': (PhysicalKeyboardKey.pageDown, LogicalKeyboardKey.pageDown),
  'control': (PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
  'shift': (PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft),
  'alt': (PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
  'meta': (PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft),
  'a': (PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA),
  'b': (PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB),
  'c': (PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC),
  'd': (PhysicalKeyboardKey.keyD, LogicalKeyboardKey.keyD),
  'e': (PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE),
  'f': (PhysicalKeyboardKey.keyF, LogicalKeyboardKey.keyF),
  'g': (PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG),
  'h': (PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH),
  'i': (PhysicalKeyboardKey.keyI, LogicalKeyboardKey.keyI),
  'j': (PhysicalKeyboardKey.keyJ, LogicalKeyboardKey.keyJ),
  'k': (PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK),
  'l': (PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL),
  'm': (PhysicalKeyboardKey.keyM, LogicalKeyboardKey.keyM),
  'n': (PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN),
  'o': (PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO),
  'p': (PhysicalKeyboardKey.keyP, LogicalKeyboardKey.keyP),
  'q': (PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ),
  'r': (PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR),
  's': (PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS),
  't': (PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT),
  'u': (PhysicalKeyboardKey.keyU, LogicalKeyboardKey.keyU),
  'v': (PhysicalKeyboardKey.keyV, LogicalKeyboardKey.keyV),
  'w': (PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW),
  'x': (PhysicalKeyboardKey.keyX, LogicalKeyboardKey.keyX),
  'y': (PhysicalKeyboardKey.keyY, LogicalKeyboardKey.keyY),
  'z': (PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ),
  '0': (PhysicalKeyboardKey.digit0, LogicalKeyboardKey.digit0),
  '1': (PhysicalKeyboardKey.digit1, LogicalKeyboardKey.digit1),
  '2': (PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2),
  '3': (PhysicalKeyboardKey.digit3, LogicalKeyboardKey.digit3),
  '4': (PhysicalKeyboardKey.digit4, LogicalKeyboardKey.digit4),
  '5': (PhysicalKeyboardKey.digit5, LogicalKeyboardKey.digit5),
  '6': (PhysicalKeyboardKey.digit6, LogicalKeyboardKey.digit6),
  '7': (PhysicalKeyboardKey.digit7, LogicalKeyboardKey.digit7),
  '8': (PhysicalKeyboardKey.digit8, LogicalKeyboardKey.digit8),
  '9': (PhysicalKeyboardKey.digit9, LogicalKeyboardKey.digit9),
};
