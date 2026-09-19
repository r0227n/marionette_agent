import 'dart:async';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../backend/backend.dart';
import 'action_policy.dart';
import '../protocol/protocol.dart';

/// A failed job never poisons later work. Expired queued jobs never execute.
class SerialQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// One connection generation and observation state. Queue survives across reconnects.
class Session {
  Session(this.name);
  final String name;
  final queue = SerialQueue();
  Uri? uri;
  Backend? backend;
  RunningApplication? application;
  String status = 'disconnected';
  int epoch = 0;
  int pending = 0;
  bool closed = false;
  Json? policy;
  PendingAction? approval;
  // Set by SnapshotService; lifecycle owns invalidation, not command handlers.
  Object? observation;
  void invalidate() {
    observation = null;
  }

  // Only active executions register here; completed requests retain no listener.
  final _shutdownListeners = <void Function()>{};
  void interrupt() {
    for (final listener in _shutdownListeners.toList()) {
      listener();
    }
  }

  /// Invalidate delayed response immediately and dispose the old connection asynchronously.
  Future<void> discard() {
    epoch++;
    approval = null;
    status = 'disconnected';
    invalidate();
    final old = backend;
    backend = null;
    if (old != null) {
      // Generation is retired immediately. Disposal may wait for upstream I/O.
      final disposal = Future<void>.sync(old.disconnect);
      unawaited(disposal.catchError((Object _) {}));
      return disposal;
    }
    return Future.value();
  }
}

/// Lifetime of one queue entry, including preflight and a single UI dispatch.
class Execution {
  Execution(
    this.request,
    this.session, {
    int? initialEpoch,
    this.parentCheck,
    this.onRetire,
  }) : epoch = initialEpoch ?? session.epoch;
  final void Function()? parentCheck, onRetire;
  final Request request;
  final Session session;
  int epoch;
  bool cancelled = false;
  bool sent = false;
  bool _finished = false;
  void check() {
    parentCheck?.call();
    request.checkDeadline();
    if (cancelled || _finished || session.epoch != epoch) {
      throw const AgentError(
        'CONNECTION_LOST',
        'Connection generation retired',
      );
    }
  }

  void requireConnected() {
    check();
    if (session.status != 'connected' || session.backend == null) {
      throw const AgentError(
        'NOT_CONNECTED',
        'Session is not connected',
        hint: 'Run connect, then snapshot',
      );
    }
  }

  Future<T> read<T>(Future<T> Function(Backend) call) async {
    requireConnected();
    final result = await call(session.backend!);
    check();
    return result;
  }

  /// Invalidate all refs right before send; dispatch one action per request.
  Future<void> mutate(
    Future<void> Function(Backend) call, {
    bool invalidate = true,
  }) async {
    requireConnected();
    if (sent) {
      throw const AgentError(
        'INTERNAL_ERROR',
        'A command may dispatch only one UI operation',
      );
    }
    if (invalidate) session.invalidate();
    sent = true;
    await call(session.backend!);
    check();
  }

  /// Cancel this child and retire only its original connection generation.
  void retire() {
    cancelled = true;
    onRetire?.call();
    if (session.epoch == epoch) session.discard();
  }

  /// Watch the deadline and classify outcomes using only this step's dispatch.
  Future<T> bound<T>(Future<T> Function() operation) async {
    check();
    final interrupted = Completer<T>();
    void interrupt() => interrupted.completeError(
      const AgentError('CONNECTION_LOST', 'Connection generation retired'),
    );
    session._shutdownListeners.add(interrupt);
    try {
      return await Future.any<T>([Future.sync(operation), interrupted.future])
          .timeout(request.remaining);
    } on TimeoutException {
      retire();
      throw AgentError(
        'TIMEOUT',
        'Request deadline exceeded',
        hint: 'Run connect, then snapshot; a sent operation may have completed',
        outcome: sent ? Outcome.unknown : Outcome.notSent,
      );
    } on AgentError catch (error) {
      if (['CONNECTION_LOST', 'TIMEOUT'].contains(error.code) ||
          (sent && error.outcome == Outcome.unknown)) {
        retire();
        throw error.withOutcome(sent ? Outcome.unknown : Outcome.notSent);
      }
      throw error.withOutcome(sent ? Outcome.failed : Outcome.notSent);
    } catch (_) {
      // Unknown transport/handler failure after dispatch cannot prove failure.
      if (sent) retire();
      throw AgentError(
        'INTERNAL_ERROR',
        'Command failed',
        outcome: sent ? Outcome.unknown : Outcome.notSent,
      );
    } finally {
      session._shutdownListeners.remove(interrupt);
      _finished = true;
    }
  }
}
