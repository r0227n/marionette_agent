import 'package:logging/logging.dart';
import 'package:marionette_agent/src/diagnostics/diagnostic_logging.dart';
import 'package:test/test.dart';

void main() {
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
