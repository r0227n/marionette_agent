import 'dart:async';
import 'dart:io';

/// Platform termination requests. Cancelling the subscription releases all
/// native signal listeners; callers own their application's shutdown sequence.
Stream<void> terminationRequests() {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  late StreamController<void> controller;
  controller = StreamController<void>(
    onListen: () {
      final signals = [
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ];
      for (final signal in signals) {
        subscriptions.add(signal.watch().listen((_) => controller.add(null)));
      }
    },
    onCancel: () async {
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    },
  );
  return controller.stream;
}
