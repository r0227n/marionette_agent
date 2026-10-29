import 'dart:async';
import 'dart:io';

import 'package:marionette_agent/src/cli/process_runner.dart';
import 'package:test/test.dart';

void main() {
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));

  test('collects both pipes and preserves a nonzero exit code', () async {
    final result = await runProcessUntil('/bin/sh', [
      '-c',
      'printf output; printf diagnostic >&2; exit 7',
    ], deadline());
    expect(result.exitCode, 7);
    expect(result.stdout, 'output');
    expect(result.stderr, 'diagnostic');
  });

  test('closes unused stdin before waiting for process exit', () async {
    final result = await runProcessUntil('/bin/cat', [], deadline());
    expect(result.exitCode, 0);
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  test('invalid UTF-8 is observed before a long-running child exits', () async {
    await expectLater(
      runProcessUntil('/bin/sh', [
        '-c',
        r"printf '\377' >&2; exec sleep 30",
      ], deadline()),
      throwsFormatException,
    );
  });

  test('timeout terminates the owned process', () async {
    final directory = await Directory.systemTemp.createTemp('mra-process-');
    final pidFile = File('${directory.path}/pid');
    try {
      final result = runProcessUntil('/bin/sh', [
        '-c',
        r'echo $$ > "$1"; exec sleep 30',
        'fixture',
        pidFile.path,
      ], DateTime.now().add(const Duration(seconds: 1)));
      await expectLater(result, throwsA(isA<TimeoutException>()));
      final childPid = int.parse(await pidFile.readAsString());
      final end = deadline();
      while (Process.killPid(childPid, ProcessSignal.sigcont)) {
        if (DateTime.now().isAfter(end)) fail('Owned child was not stopped');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('an expired request fails before executable lookup', () async {
    await expectLater(
      runProcessUntil(
        '/nonexistent/mra-expired-process',
        [],
        DateTime.now().subtract(const Duration(seconds: 1)),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
