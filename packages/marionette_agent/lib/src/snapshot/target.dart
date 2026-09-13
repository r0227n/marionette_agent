import '../backend/backend.dart';
import '../protocol/protocol.dart';

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

/// A selection made within this command, retaining the observed identity until send.
/// Never serialized as a public ref or accepted from IPC.
class ObservedQuery extends TargetQuery {
  const ObservedQuery(this.selector, this.element);
  final Selector selector;
  final ElementInfo element;
}

class ResolvedElement {
  const ResolvedElement(this.selector, this.element);
  final Selector selector;
  final ElementInfo element;
}
