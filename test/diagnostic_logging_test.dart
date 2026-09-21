import 'package:logging/logging.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:test/test.dart';

void main() {
  test(
    'debug metadata is opt-in and cannot include arbitrary errors',
    () async {
      final lines = <String>[];
      final subscription = configureDiagnosticLogging(lines.add);
      addTearDown(subscription.cancel);
      DebugDiagnostics(
        enabled: false,
        requestId: 'off',
        session: 'off',
      ).emit(DebugStage.cliResult, code: 'OK');
      expect(lines, isEmpty);
      DebugDiagnostics(
        enabled: true,
        requestId: 'request-1',
        session: 'demo',
      ).emit(DebugStage.cliResult, code: 'BACKEND_ERROR');
      DebugDiagnostics(
        enabled: true,
        requestId: 'http://secret/token',
        session: 'app\ntext',
      ).emit(DebugStage.cliResult, code: 'fill-secret');
      expect(
        lines.first,
        matches(
          r'requestId=request-1 session=demo stage=cliResult elapsedMs=\d+ code=BACKEND_ERROR$',
        ),
      );
      expect(lines.last, contains('requestId=none session=none'));
      expect(lines.last, endsWith('code=INTERNAL_ERROR'));
      expect(lines.join(), isNot(contains('secret')));
      DebugDiagnostics(
        enabled: true,
        requestId: 'close',
        session: null,
      ).emit(DebugStage.cliResult, code: 'CLOSE_FAILED');
      expect(lines.last, endsWith('code=CLOSE_FAILED'));
    },
  );

  test('concurrent debug collectors retain request ownership', () async {
    final subscription = configureDiagnosticLogging((_) {});
    addTearDown(subscription.cancel);
    final buffers = [<DiagnosticEntry>[], <DiagnosticEntry>[]];
    await Future.wait(
      List.generate(
        2,
        (i) => captureDiagnostics(buffers[i], () async {
          final debug = DebugDiagnostics(
            enabled: true,
            requestId: 'r$i',
            session: 's$i',
          );
          debug.emit(DebugStage.daemonDispatch);
          await Future<void>.delayed(Duration.zero);
          debug.emit(DebugStage.daemonResult, code: i == 0 ? 'OK' : 'TIMEOUT');
        }),
      ),
    );
    for (var i = 0; i < 2; i++) {
      expect(buffers[i], hasLength(2));
      for (final entry in buffers[i]) {
        expect(entry.message, contains('requestId=r$i session=s$i'));
        expect(entry.message, isNot(contains('requestId=r${1 - i}')));
      }
    }
  });
  test('writes safe INFO diagnostics and suppresses verbose details', () async {
    final lines = <String>[];
    final subscription = configureDiagnosticLogging(lines.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = Level.INFO;
    });

    final logger = Logger('VmServiceConnector');
    logger.info(
      'Connecting to VM service at '
      'ws://user:password@localhost:1234/token/ws?auth=secret',
    );
    logger.fine('Calling extension with entered text: super-secret-input');
    logger.severe(
      'Connection failed',
      Exception('ws://localhost:1234/token/ws?auth=secret'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(lines, [
      '[INFO] VmServiceConnector: Connecting to VM service at <redacted-uri>',
      '[SEVERE] VmServiceConnector: Connection failed',
    ]);
    expect(lines.join('\n'), isNot(contains('password')));
    expect(lines.join('\n'), isNot(contains('super-secret-input')));
    expect(lines.join('\n'), isNot(contains('auth=secret')));
  });

  test('captures daemon diagnostics and replays them in the CLI', () async {
    final lines = <String>[];
    final subscription = configureDiagnosticLogging(lines.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = Level.INFO;
    });
    final entries = <DiagnosticEntry>[];

    await captureDiagnostics(entries, () async {
      Logger('backend').warning('Retry disabled');
    });
    await Future<void>.delayed(Duration.zero);
    expect(lines, isEmpty);

    replayDiagnostics(entries.map((entry) => entry.toJson()).toList());
    await Future<void>.delayed(Duration.zero);
    expect(lines, ['[WARNING] backend: Retry disabled']);
  });

  test('keeps concurrent request diagnostics separate', () async {
    final subscription = configureDiagnosticLogging((_) {});
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = Level.INFO;
    });
    final first = <DiagnosticEntry>[];
    final second = <DiagnosticEntry>[];

    await Future.wait([
      captureDiagnostics(first, () async {
        Logger('first').info('before await');
        await Future<void>.delayed(Duration.zero);
        Logger('first').info('after await');
      }),
      captureDiagnostics(second, () async {
        await Future<void>.delayed(Duration.zero);
        Logger('second').info('separate request');
      }),
    ]);

    expect(first.map((entry) => entry.loggerName), ['first', 'first']);
    expect(second.map((entry) => entry.loggerName), ['second']);
  });
}
