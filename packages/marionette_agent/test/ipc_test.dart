import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory runtime;
  final script = File('test/support/fake_cli.dart').absolute.path;
  Future<ProcessResult> cli(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    [script, '--json', ...args],
    environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
  );
  Map<String, dynamic> body(ProcessResult result) {
    expect(result.stderr, '');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  setUp(() async {
    runtime = await Directory('/tmp').createTemp('mra-test-');
    await Process.run('chmod', ['700', runtime.path]);
  });
  tearDown(() async {
    for (final session in ['a', 'b', 'default']) {
      await cli(['--session', session, 'close']);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (await runtime.exists()) await runtime.delete(recursive: true);
  });
  test(
    'absence is read-only; simultaneous startup preserves separate sessions',
    () async {
      expect(body(await cli(['session', 'list']))['data'], {'sessions': []});
      expect(File('${runtime.path}/s').existsSync(), false);
      final starts = await Future.wait([
        cli(['--session', 'a', 'connect', 'http://localhost:1/']),
        cli(['--session', 'b', 'connect', 'http://localhost:2/']),
      ]);
      for (final result in starts) {
        expect(body(result)['ok'], true);
      }
      for (var i = 1; i <= 3; i++) {
        expect(body(await cli(['--session', 'a', 'count']))['data'], {
          'calls': i,
        });
      }
      expect(body(await cli(['--session', 'b', 'count']))['data'], {
        'calls': 1,
      });
      final concurrent = await Future.wait(
        List.generate(4, (_) => cli(['--session', 'a', 'count'])),
      );
      final counts =
          concurrent
              .map((r) => (body(r)['data'] as Map)['calls'] as int)
              .toList()
            ..sort();
      expect(counts, [4, 5, 6, 7]);
      final listing = body(await cli(['session', 'list']))['data'] as Map;
      expect((listing['sessions'] as List).length, 2);
      expect(body(await cli(['--session', 'a', 'close']))['ok'], true);
      expect(body(await cli(['--session', 'b', 'count']))['data'], {
        'calls': 2,
      });
      expect(body(await cli(['--session', 'b', 'close']))['ok'], true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(File('${runtime.path}/daemon.json').existsSync(), false);
      expect(body(await cli(['session', 'list']))['data'], {'sessions': []});
    },
    timeout: Timeout(const Duration(seconds: 60)),
  );
  test('stale socket recovery and private runtime files', () async {
    final socket = await ServerSocket.bind(
      InternetAddress('${runtime.path}/s', type: InternetAddressType.unix),
      0,
    );
    await socket.close();
    expect(body(await cli(['connect', 'http://localhost:1/']))['ok'], true);
    final metadata = File('${runtime.path}/daemon.json').readAsStringSync();
    expect(metadata, isNot(contains('localhost')));
    for (final name in ['s', 'daemon.json', 'daemon.lock', 'launch.lock']) {
      final stat = await Process.run('stat', [
        '-f',
        '%Lp',
        '${runtime.path}/$name',
      ]);
      expect((stat.stdout as String).trim(), '600');
    }
  });
  test('daemon logging records are replayed on CLI stderr', () async {
    expect(body(await cli(['connect', 'http://localhost:1/']))['ok'], true);

    final result = await cli(['log']);
    expect(jsonDecode(result.stdout as String), containsPair('ok', true));
    expect(result.stderr, '[INFO] fake-daemon: Request handled\n');
  });
  test('compiled executable starts the same binary in daemon mode', () async {
    final executable = '${runtime.path}/cli';
    final build = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      script,
      '-o',
      executable,
    ]);
    expect(build.exitCode, 0, reason: 'Compilation failed');
    Future<ProcessResult> compiled(List<String> args) => Process.run(
      executable,
      ['--json', ...args],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
    );
    expect(
      body(await compiled(['connect', 'http://localhost:1/']))['ok'],
      true,
    );
    expect(body(await compiled(['count']))['data'], {'calls': 1});
    expect(body(await compiled(['count']))['data'], {'calls': 2});
    expect(body(await compiled(['close']))['ok'], true);
  }, timeout: Timeout(const Duration(seconds: 60)));
}
