import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:marionette_agent_util/src/recording/platform_recorder.dart';
import 'package:test/test.dart';

class CommandProcess implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exit = Completer<int>();
  final signals = <ProcessSignal>[];
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CommandProcess process;
  Future<String> run([int ms = 1000]) => consumeRecordingCommand(
    process,
    DateTime.now().add(Duration(milliseconds: ms)),
  );
  setUp(() => process = CommandProcess());
  tearDown(() async {
    if (!process.exit.isCompleted) process.exit.complete(0);
    await process.output.close();
    await process.errors.close();
  });
  test('invalid stdout followed by done is handled once before exit', () async {
    final result = run();
    final assertion = expectLater(result, throwsFormatException);
    process.output.add([0xff]);
    unawaited(process.output.close());
    await assertion;
    expect(process.signals, [ProcessSignal.sigkill]);
  });
  test('stderr failure is handled before process exits', () async {
    final result = run();
    final error = StateError('stderr read failed');
    final assertion = expectLater(result, throwsA(same(error)));
    process.errors.addError(error);
    await assertion;
    expect(process.signals, [ProcessSignal.sigkill]);
  });
  test('deadline bounds inherited pipes and consumes late errors', () async {
    final result = run(10);
    process.exit.complete(0);
    await expectLater(
      result,
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
      ),
    );
    expect(process.signals, [ProcessSignal.sigkill]);
    process.errors.addError(StateError('late stderr error'));
    process.output.addError(StateError('late stdout error'));
    await Future<void>.delayed(Duration.zero);
  });
  test('normal completion waits for both pipes', () async {
    final result = run();
    process.exit.complete(0);
    process.output.add([111, 107]);
    await process.output.close();
    await process.errors.close();
    expect(await result, 'ok');
    expect(process.signals, isEmpty);
  });
}
