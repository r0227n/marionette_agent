import 'dart:async';

import '../backend/backend.dart';
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
  String status = 'disconnected';
  int epoch = 0;
  int pending = 0;
  bool closed = false;
  // Set by SnapshotService; lifecycle owns invalidation, not command handlers.
  Object? observation;
  void invalidate() {
    observation = null;
  }

  /// Invalidate delayed response immediately and dispose the old connection asynchronously.
  void discard() {
    epoch++;
    status = 'disconnected';
    invalidate();
    final old = backend;
    backend = null;
    if (old != null) {
      // Generation is retired immediately. Disposal may wait for upstream I/O.
      unawaited(old.disconnect().catchError((Object _) {}));
    }
  }
}

/// Lifetime of one queue entry, including preflight and a single UI dispatch.
class Execution {
  Execution(this.request, this.session) : epoch = session.epoch;
  final Request request;
  final Session session;
  int epoch;
  bool cancelled = false;
  bool sent = false;
  void check() {
    request.checkDeadline();
    if (cancelled || session.epoch != epoch) {
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
  Future<void> mutate(Future<void> Function(Backend) call) async {
    requireConnected();
    if (sent) {
      throw const AgentError(
        'INTERNAL_ERROR',
        'A command may dispatch only one UI operation',
      );
    }
    session.invalidate();
    sent = true;
    await call(session.backend!);
    check();
  }

  /// Watch execution deadline and do not report uncertain post-send outcomes as not executed.
  Future<T> bound<T>(Future<T> Function() operation) async {
    request.checkDeadline();
    try {
      return await Future.sync(operation).timeout(request.remaining);
    } on TimeoutException {
      cancelled = true;
      session.discard();
      throw AgentError(
        'TIMEOUT',
        'Request deadline exceeded',
        hint: 'Run connect, then snapshot; a sent operation may have completed',
        outcome: sent ? Outcome.unknown : Outcome.notSent,
      );
    } on AgentError catch (error) {
      if (['CONNECTION_LOST', 'TIMEOUT'].contains(error.code) ||
          (sent && error.outcome == Outcome.unknown)) {
        cancelled = true;
        session.discard();
        throw error.withOutcome(sent ? Outcome.unknown : Outcome.notSent);
      }
      throw error.withOutcome(sent ? Outcome.failed : Outcome.notSent);
    } catch (_) {
      // Unknown transport/handler failure after dispatch cannot prove failure.
      if (sent) session.discard();
      throw AgentError(
        'INTERNAL_ERROR',
        'Command failed',
        outcome: sent ? Outcome.unknown : Outcome.notSent,
      );
    }
  }
}
