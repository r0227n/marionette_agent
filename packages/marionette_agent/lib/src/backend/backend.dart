import 'package:collection/collection.dart';

import '../protocol/protocol.dart';

/// Matching attributes supported by the backend; check availability via Backend.selectors.
enum SelectorKind { key, identifier, text, type }

/// Exact-match condition by a single attribute; do not create implicit precedence across multiple criteria.
class Selector {
  const Selector(this.kind, this.value);
  final SelectorKind kind;
  final String value;
  Json toJson() => {kind.name: value};
}

/// Finite non-negative coordinates in Flutter logical pixels.
class Point {
  Point(this.x, this.y) {
    if (!x.isFinite || !y.isFinite || x < 0 || y < 0) {
      invalid('Coordinates must be finite and non-negative');
    }
  }
  final double x, y;
}

/// Exclusive types for element-targeted tap and explicit coordinate targets.
sealed class TapTarget {
  const TapTarget();
}

/// Target values validated for uniqueness by CommandContext before passing to backend.
class ElementTarget extends TapTarget {
  const ElementTarget(this.selector);
  final Selector selector;
}

/// User-supplied coordinates; never use these as implicit fallback for refs.
class CoordinateTarget extends TapTarget {
  const CoordinateTarget(this.point);
  final Point point;
}

/// Finger movement direction, not destination content movement.
enum Direction { left, right, up, down }

/// Swipe primitive shared with scroll behavior in the backend.
sealed class SwipeGesture {
  const SwipeGesture();
}

/// Gesture specified by element center, direction, and distance.
class ElementSwipe extends SwipeGesture {
  ElementSwipe(this.selector, this.direction, {this.distance = 200}) {
    if (!distance.isFinite || distance <= 0) {
      invalid('Distance must be finite and positive');
    }
  }
  final Selector selector;
  final Direction direction;
  final double distance;
}

/// Explicit coordinate gesture connecting two distinct points.
class CoordinateSwipe extends SwipeGesture {
  CoordinateSwipe(this.start, this.end) {
    if (start.x == end.x && start.y == end.y) {
      invalid('Swipe endpoints must differ');
    }
  }
  final Point start, end;
}

/// Immutable DTO containing only attributes observed from inspect results.
class ElementInfo {
  ElementInfo({
    this.type,
    this.text,
    this.key,
    this.identifier,
    Json? bounds,
    this.visible,
    this.textMatchable = false,
  }) : bounds = bounds == null ? null : Map.unmodifiable(bounds);
  final String? type, text, key, identifier;
  final Json? bounds;
  final bool? visible;

  /// True only when discovery text is known to follow the backend matcher.
  final bool textMatchable;
  String? value(SelectorKind kind) => switch (kind) {
    SelectorKind.key => key,
    SelectorKind.identifier => identifier,
    SelectorKind.text => textMatchable ? text : null,
    SelectorKind.type => type,
  };
  Json toJson() => {
    if (type != null) 'type': type,
    if (text != null) 'text': text,
    if (key != null) 'key': key,
    if (identifier != null) 'identifier': identifier,
    if (bounds != null) 'bounds': bounds,
    if (visible != null) 'visible': visible,
  };
  bool sameAs(ElementInfo other) =>
      const DeepCollectionEquality().equals(toJson(), other.toJson()) &&
      textMatchable == other.textMatchable;
}

/// Finite log range. Backends that cannot distinguish unset from empty array should return constraints.
class LogBatch {
  const LogBatch(this.entries, {this.configured, this.limitation});
  final List<String> entries;
  final bool? configured;
  final String? limitation;
}

/// Typed backend boundary where each Session owns one instance per connection.
/// Implementations must not resend operations or leak upstream maps/exceptions from this boundary.
abstract interface class Backend {
  Set<SelectorKind> get selectors;

  /// Connect to VM Service. Session owns teardown on failure or deadline expiration.
  Future<void> connect(Uri uri);

  /// Disconnect. Duplicate calls are tolerated and must not terminate the app.
  Future<void> disconnect();

  /// Health probe: connector.isConnected alone does not detect a dead socket.
  Future<void> checkConnection();

  /// Inspect interactive and readable element info. This is not a full widget tree.
  Future<List<ElementInfo>> inspect();

  /// Send exactly one tap for validated target.
  Future<void> tap(TapTarget target);

  /// Replace text field value; empty text clears it. Do not log text in diagnostics.
  Future<void> fill(Selector selector, String text);

  /// Send one gesture. A successful gesture does not guarantee screen navigation.
  Future<void> swipe(SwipeGesture gesture);

  /// PNG base64 payload list. Saving and overwrite prevention are caller CLI responsibilities.
  Future<List<String>> captureScreenshots();

  /// Read bounded logs retained by the binding without subscribing.
  Future<LogBatch> readLogs();
}

/// Factory for creating a new connector during reconnect, never reusing old connector instances.
typedef BackendFactory = Backend Function();
