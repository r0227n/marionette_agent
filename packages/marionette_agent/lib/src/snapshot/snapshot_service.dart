import 'dart:async';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../session/session.dart';

/// TargetQuery that represents exactly one of ref or selector.

sealed class TargetQuery {
  const TargetQuery();
}

/// Short refs for the latest public snapshot; never reused across sessions.
class RefQuery extends TargetQuery {
  RefQuery(this.ref) {
    if (!RegExp(r'^@e[1-9][0-9]*$').hasMatch(ref)) {
      invalid('Expected a ref such as @e1');
    }
  }
  final String ref;
}

/// Backend exact-match condition; must uniquely match the pre-action observation.

class SelectorQuery extends TargetQuery {
  const SelectorQuery(this.selector);
  final Selector selector;
}

/// Immutable ref and observed attributes kept only in public snapshots.
class _Reference {
  const _Reference(this.selector, this.element);
  final Selector selector;
  final ElementInfo element;
}

class _Observation {
  _Observation(this.generation, this.refs);
  final int generation;
  final Map<String, _Reference> refs;
}

/// One instance per daemon.
/// Source of truth for numbering, uniqueness checks, and pre-action re-observation.
///
/// Observation and action are not atomic at the upstream API level. Do not implicitly fallback to coordinates.
class SnapshotService {
  int _nextRef = 1;
  int _generation = 0;

  /// Invalidate stale refs and expose only data and uniquely actionable refs.

  Future<Json> publish(Execution context) async {
    context.requireConnected();
    context.session.invalidate();
    final elements = await context.read((backend) => backend.inspect());
    final selectors = context.session.backend!.selectors;
    final refs = <String, _Reference>{};
    final rows = <Json>[];
    final counts = {for (final kind in selectors) kind: <String, int>{}};
    for (var i = 0; i < elements.length; i++) {
      if (i % 256 == 0) await _yield(context);
      for (final kind in selectors) {
        final value = elements[i].candidateValue(kind);
        if (value != null && value.isNotEmpty) {
          counts[kind]!.update(value, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    for (var i = 0; i < elements.length; i++) {
      if (i % 256 == 0) await _yield(context);
      final element = elements[i];
      Selector? selected;
      if (element.visible != false) {
        for (final kind in SelectorKind.values) {
          final value = element.value(kind);
          if (!selectors.contains(kind) || value == null || value.isEmpty) {
            continue;
          }
          final candidate = Selector(kind, value);
          if (counts[kind]![value] == 1) {
            selected = candidate;
            break;
          }
        }
      }
      final row = element.toJson();
      if (selected == null) {
        row['reason'] = element.visible == false
            ? 'not_visible'
            : 'no_unique_supported_selector';
      } else {
        final ref = '@e${_nextRef++}';
        row['ref'] = ref;
        refs[ref] = _Reference(selected, element);
      }
      rows.add(row);
    }
    context.check();
    final observation = _Observation(++_generation, Map.unmodifiable(refs));
    context.session.observation = observation;
    return {'generation': observation.generation, 'elements': rows};
  }

  Future<void> _yield(Execution context) async {
    context.check();
    await Future<void>.delayed(Duration.zero);
    context.check();
  }

  /// Re-match stored selector and validate attribute changes; do not issue a ref here.
  Future<Selector> resolve(Execution context, TargetQuery target) async {
    context.requireConnected();
    _Reference? reference;
    final Selector selector;
    switch (target) {
      case RefQuery(:final ref):
        final observation = context.session.observation;
        reference = observation is _Observation ? observation.refs[ref] : null;
        if (reference == null) {
          throw const AgentError(
            'STALE_REF',
            'Ref is not valid in this session',
            hint: 'Run snapshot again',
          );
        }
        selector = reference.selector;
      case SelectorQuery(selector: final selected):
        selector = selected;
    }
    if (!context.session.backend!.selectors.contains(selector.kind)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support this selector',
      );
    }
    final elements = await context.read((backend) => backend.inspect());
    final matches = _matches(elements, selector);
    if (matches.length > 1) {
      throw const AgentError(
        'AMBIGUOUS_TARGET',
        'Multiple elements match',
        hint: 'Use a unique key or identifier',
      );
    }
    if (matches.isEmpty) {
      if (reference != null) {
        throw const AgentError(
          'STALE_REF',
          'Target disappeared or changed',
          hint: 'Run snapshot again',
        );
      }
      throw const AgentError('TARGET_NOT_FOUND', 'No element matches');
    }
    final element = matches.single;
    if (selector.kind == SelectorKind.text && !element.textMatchable) {
      throw const AgentError(
        'UNRESOLVABLE_TARGET',
        'Displayed text does not map to a verified backend text matcher',
        hint: 'Use a key or a unique supported type',
      );
    }
    if (reference != null && !reference.element.sameAs(element)) {
      throw const AgentError(
        'STALE_REF',
        'Target attributes changed',
        hint: 'Run snapshot again',
      );
    }
    if (element.visible == false) {
      throw const AgentError('UNRESOLVABLE_TARGET', 'Target is not visible');
    }
    return selector;
  }

  List<ElementInfo> _matches(List<ElementInfo> elements, Selector selector) =>
      elements
          .where(
            (element) =>
                element.candidateValue(selector.kind) == selector.value,
          )
          .toList();
}
