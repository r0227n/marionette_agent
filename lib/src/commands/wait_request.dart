import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/target.dart';
import 'arguments.dart';

const defaultWaitState = 'exists';
const waitStates = ['exists', 'gone'];
const defaultWaitPollIntervalMs = 100;
const minimumWaitPollIntervalMs = 50;
const maximumWaitPollIntervalMs = 1000;

/// Complete, side-effect-free validation shared by CLI and execution.
sealed class WaitRequest {
  const WaitRequest();

  factory WaitRequest.parse(Json params) {
    if (params.containsKey('milliseconds')) {
      final ms = params['milliseconds'];
      if (params.length != 1 || ms is! int || ms < 0) {
        invalid('Invalid wait duration');
      }
      parseDurationMs('$ms', allowZero: true);
      return DurationWait._(ms);
    }
    final allowed = {
      'ref',
      ...SelectorKind.values.map((kind) => kind.name),
      'state',
      'pollIntervalMs',
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown wait parameter');
    }
    final state = params.containsKey('state')
        ? params['state']
        : defaultWaitState;
    if (state is! String || !waitStates.contains(state)) {
      invalid('Wait state must be exists or gone');
    }
    final interval = params.containsKey('pollIntervalMs')
        ? params['pollIntervalMs']
        : defaultWaitPollIntervalMs;
    if (interval is! int ||
        interval < minimumWaitPollIntervalMs ||
        interval > maximumWaitPollIntervalMs) {
      invalid(
        'Poll interval must be an integer from '
        '$minimumWaitPollIntervalMs to $maximumWaitPollIntervalMs',
      );
    }
    return TargetWait._(decodeTarget(params), state, interval);
  }

  Json toJson();
}

final class DurationWait extends WaitRequest {
  const DurationWait._(this.milliseconds);
  final int milliseconds;

  @override
  Json toJson() => {'milliseconds': milliseconds};
}

final class TargetWait extends WaitRequest {
  const TargetWait._(this.target, this.state, this.pollIntervalMs);
  final TargetQuery target;
  final String state;
  final int pollIntervalMs;

  @override
  Json toJson() => {
    ...switch (target) {
      RefQuery(:final ref) => {'ref': ref},
      SelectorQuery(:final selector) => selector.toJson(),
      ObservedQuery() => throw StateError('Wait requires a public target'),
    },
    'state': state,
    'pollIntervalMs': pollIntervalMs,
  };
}
