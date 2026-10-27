import 'dart:convert';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import '../platform/screen_capture.dart';
import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../session/session.dart';
import '../snapshot/snapshot_service.dart';
import '../snapshot/target.dart';

/// Shared execution boundary used by individual command implementations.
///
/// Handler validates args and calls one of [performTarget], [performCoordinates], or [read].
/// Do not reimplement session queueing, deadline handling, ref invalidation, or indeterminate-result classification.
class CommandContext {
  CommandContext(
    this._execution,
    this._snapshots, {
    ScreenCapturer? screenCapturer,
  }) : _screenCapturer = screenCapturer ?? platformScreenCapturer();
  final ScreenCapturer _screenCapturer;
  final Execution _execution;
  final SnapshotService _snapshots;

  /// Absolute caller deadline. Use this deadline when adding file or similar operations.
  DateTime get deadline => _execution.request.deadline;

  /// Session name targeted by the action. Never expose URI or input text in diagnostics.
  String get session => _execution.session.name;

  /// Verify this step and its parent before publishing a computed read result.
  void check() => _execution.check();

  /// Fetch a new public snapshot. This emits refs, unlike pre-observation.
  Future<Json> snapshot({
    Selector? filter,
    bool interactive = false,
    bool compact = false,
    int? depth,
  }) => _snapshots.publish(
    _execution,
    filter: filter,
    interactive: interactive,
    compact: compact,
    depth: depth,
  );

  Future<void> requireInteraction(String action) => read((backend) async {
    if (backend is! InteractionBackend ||
        !(backend as InteractionBackend).interactions.contains(action)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support this interaction',
      );
    }
  });

  Future<Selector> referenceSelector(RefQuery ref) async =>
      _snapshots.referenceSelector(_execution, ref);

  /// Resolve a selection to a unique supported matcher, never an index or coordinate fallback.
  Future<ObservedQuery> uniqueTarget(ElementInfo element) =>
      _snapshots.uniqueTarget(_execution, element);

  /// Re-observe one target without changing the published refs.
  Future<ElementInfo> observeTarget(TargetQuery query) =>
      _snapshots.observeTarget(_execution, query);

  /// OS observation shares the queue/deadline but never requires a Flutter backend.
  Future<Json> captureDeviceScreen(String source, String device) async {
    check();
    if (source == 'ios-device') {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Physical iOS screenshots require a signed XCTest runner; not implemented or verified',
      );
    }
    try {
      final image = await _screenCapturer.capture(device, deadline);
      check();
      return {
        'images': [base64Encode(image.png)],
        'capture': image.metadata,
      };
    } on PlatformException catch (error) {
      throw AgentError(error.code, error.message, hint: error.hint);
    }
  }

  /// Read flow. Validate connection generation and deadline before and after await; do not invalidate refs.
  Future<T> read<T>(Future<T> Function(Backend) operation) =>
      _execution.read(operation);

  Future<ResolvedElement> resolveRead(TargetQuery query) =>
      _snapshots.resolveRead(_execution, query);

  Future<List<ElementInfo>> count(Selector selector) =>
      _snapshots.count(_execution, selector);

  /// Validate uniqueness and target attributes, invalidate all refs, and send one UI action.
  ///
  /// Call backend primitive exactly once in callback. Complete argument parsing and validation before calling this method.
  /// Returned values do not guarantee UI state changes.
  Future<Json> performTarget(
    TargetQuery query,
    Future<void> Function(Backend, Selector) operation,
  ) async {
    final selector = await _snapshots.resolve(_execution, query);
    await _execution.mutate((backend) => operation(backend, selector));
    return {'requiresSnapshot': true};
  }

  /// Resolve every target in one observation, then invalidate and dispatch once.
  Future<Json> performTargets(
    List<TargetQuery> queries,
    Future<void> Function(Backend, List<Selector>) operation,
  ) async {
    final targets = await _snapshots.resolveAll(_execution, queries);
    if (targets.any((target) => target.element.visible == false)) {
      throw const AgentError('UNRESOLVABLE_TARGET', 'Targets must be visible');
    }
    await _execution.mutate(
      (backend) =>
          operation(backend, targets.map((target) => target.selector).toList()),
    );
    return {'requiresSnapshot': true};
  }

  /// A non-UI side effect still records delivery while preserving observed refs.
  Future<void> performEffect(Future<void> Function(Backend) operation) =>
      _execution.mutate(operation, invalidate: false);

  /// Shared dispatch path for explicit coordinate mode. Build Point values ahead of call.
  Future<Json> performCoordinates(
    Future<void> Function(Backend) operation,
  ) async {
    await _execution.mutate(operation);
    return {'requiresSnapshot': true};
  }
}
