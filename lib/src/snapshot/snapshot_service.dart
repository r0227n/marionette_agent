import 'dart:async';

import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../session/session.dart';
import 'target.dart';

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

  /// Revalidate published refs without publishing, refreshing, or invalidating.
  Future<Json> annotationTargets(Execution context) async {
    context.requireConnected();
    final observation = context.session.observation;
    if (observation is! _Observation) {
      throw const AgentError(
        'STALE_REF',
        'No valid snapshot for annotation',
        hint: 'Run snapshot again',
      );
    }
    final elements = await context.read((backend) => backend.inspect());
    final kinds = observation.refs.values
        .map((ref) => ref.selector.kind)
        .toSet();
    final index = {
      for (final kind in kinds) kind: <String, List<ElementInfo>>{},
    };
    for (var i = 0; i < elements.length; i++) {
      if (i % 256 == 0) await _yield(context);
      for (final kind in kinds) {
        final value = elements[i].candidateValue(kind);
        if (value != null) {
          index[kind]!.putIfAbsent(value, () => []).add(elements[i]);
        }
      }
    }
    final targets = <Json>[];
    for (final entry in observation.refs.entries) {
      if (targets.length % 256 == 0) await _yield(context);
      final selector = entry.value.selector;
      final matches = index[selector.kind]?[selector.value] ?? [];
      if (matches.length != 1 || !entry.value.element.sameAs(matches.single)) {
        throw const AgentError(
          'STALE_REF',
          'Snapshot changed before annotation',
          hint: 'Run snapshot again',
        );
      }
      targets.add({'ref': entry.key, 'bounds': entry.value.element.bounds});
    }
    context.check();
    return {'generation': observation.generation, 'targets': targets};
  }

  /// Invalidate stale refs and expose only data and uniquely actionable refs.

  Future<Json> publish(
    Execution context, {
    Selector? filter,
    bool interactive = false,
    bool compact = false,
    int? depth,
  }) async {
    context.requireConnected();
    context.session.invalidate();
    final elements = await context.read((backend) => backend.inspect());
    if (depth != null && elements.any((element) => element.depth == null)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not provide element depth',
      );
    }
    if (interactive && elements.any((element) => element.interactive == null)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not identify interactive elements',
      );
    }
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
      // Filtering affects delivery only, after full-observation safety and numbering.
      if (filter == null ||
          element.candidateValue(filter.kind) == filter.value) {
        if ((!interactive || element.interactive == true) &&
            (depth == null || element.depth! <= depth) &&
            (!compact ||
                row.containsKey('ref') ||
                element.text?.isNotEmpty == true ||
                element.inputValue != null ||
                element.label?.isNotEmpty == true)) {
          rows.add(row);
        }
      }
    }
    context.check();
    final observation = _Observation(++_generation, Map.unmodifiable(refs));
    context.session.observation = observation;
    final result = <String, dynamic>{
      'generation': observation.generation,
      if (interactive || compact || depth != null)
        'options': {
          'interactive': interactive,
          'compact': compact,
          'depth': depth,
        },
      if (filter != null)
        'filter': {
          'kind': filter.kind.name,
          'value': filter.value,
          'matchedCount': rows.length,
          'totalCount': elements.length,
        },
      'elements': rows,
    };
    retainPublished(context.session, result);
    return result;
  }

  /// Only delivered refs remain actionable; numbering still covers all rows.
  void retainPublished(Session session, Json data) {
    final snapshot = data['finalSnapshot'] is Map
        ? asJson(data['finalSnapshot'])
        : data;
    final observation = session.observation;
    if (observation is! _Observation ||
        snapshot['generation'] != observation.generation ||
        snapshot['elements'] is! List) {
      return;
    }
    final visible = (snapshot['elements'] as List)
        .map((row) => asJson(row)['ref'])
        .toSet();
    session.observation = _Observation(
      observation.generation,
      Map.unmodifiable({
        for (final entry in observation.refs.entries)
          if (visible.contains(entry.key)) entry.key: entry.value,
      }),
    );
  }

  Future<void> _yield(Execution context) async {
    context.check();
    await Future<void>.delayed(Duration.zero);
    context.check();
  }

  /// Re-match stored selector and validate attribute changes; do not issue a ref here.
  Future<Selector> resolve(Execution context, TargetQuery target) async {
    final resolved = await resolveRead(context, target);
    if (resolved.element.visible == false) {
      throw const AgentError('UNRESOLVABLE_TARGET', 'Target is not visible');
    }
    return resolved.selector;
  }

  Future<ElementInfo> observeTarget(
    Execution context,
    TargetQuery target,
  ) async => (await resolveRead(context, target)).element;

  /// Read-only target resolution. It re-observes and validates refs without
  /// invalidating them, so successful state queries keep the current snapshot.
  Future<ResolvedElement> resolveRead(
    Execution context,
    TargetQuery target,
  ) async => (await resolveAll(context, [target])).single;

  /// Validate all targets against the same observation. No UI work occurs here.
  Future<List<ResolvedElement>> resolveAll(
    Execution context,
    List<TargetQuery> targets,
  ) async {
    context.requireConnected();
    final references = targets
        .map((target) => _reference(context, target))
        .toList();
    for (final reference in references) {
      _requireSelector(context, reference.selector);
    }
    final elements = await context.read((backend) => backend.inspect());
    final resolved = [
      for (final reference in references)
        _resolve(reference.selector, reference.element, elements),
    ];
    context.check();
    return resolved;
  }

  ({Selector selector, ElementInfo? element}) _reference(
    Execution context,
    TargetQuery target,
  ) {
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
      case ObservedQuery(:final selector, :final element):
        return (selector: selector, element: element);
    }
    return (selector: selector, element: reference?.element);
  }

  ResolvedElement _resolve(
    Selector selector,
    ElementInfo? expected,
    List<ElementInfo> elements,
  ) {
    final matches = _matches(elements, selector);
    if (matches.length > 1) {
      throw const AgentError(
        'AMBIGUOUS_TARGET',
        'Multiple elements match',
        hint: 'Use a unique key or identifier',
      );
    }
    if (matches.isEmpty) {
      if (expected != null) {
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
    if (expected != null && !expected.sameAs(element)) {
      throw const AgentError(
        'STALE_REF',
        'Target attributes changed',
        hint: 'Run snapshot again',
      );
    }
    return ResolvedElement(selector, element);
  }

  Selector referenceSelector(Execution context, RefQuery ref) {
    context.requireConnected();
    final observation = context.session.observation;
    final reference = observation is _Observation
        ? observation.refs[ref.ref]
        : null;
    if (reference == null) {
      throw const AgentError(
        'STALE_REF',
        'Ref is not valid in this session',
        hint: 'Run snapshot again',
      );
    }
    return reference.selector;
  }

  Future<ObservedQuery> uniqueTarget(
    Execution context,
    ElementInfo element,
  ) async {
    context.requireConnected();
    final elements = await context.read((backend) => backend.inspect());
    for (final kind in SelectorKind.values) {
      if (!context.session.backend!.selectors.contains(kind)) continue;
      final value = element.value(kind);
      if (value == null || value.isEmpty) continue;
      final selector = Selector(kind, value);
      final matches = _matches(elements, selector);
      if (matches.length == 1 && matches.single.sameAs(element)) {
        context.check();
        return ObservedQuery(selector, element);
      }
    }
    throw const AgentError(
      'UNRESOLVABLE_TARGET',
      'Selected element has no unique supported matcher',
    );
  }

  /// Count selector candidates without requiring uniqueness.
  Future<List<ElementInfo>> count(Execution context, Selector selector) async {
    context.requireConnected();
    _requireSelector(context, selector);
    final elements = await context.read((backend) => backend.inspect());
    return _matches(elements, selector);
  }

  void _requireSelector(Execution context, Selector selector) {
    if (!context.session.backend!.selectors.contains(selector.kind)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support this selector',
      );
    }
  }

  List<ElementInfo> _matches(List<ElementInfo> elements, Selector selector) =>
      elements
          .where(
            (element) =>
                element.candidateValue(selector.kind) == selector.value,
          )
          .toList();
}
