import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('installed and upgraded AOT CLI retains a relocatable matching skill bundle', () async {
    final temp = Directory(Directory.systemTemp.resolveSymbolicLinksSync())
        .createTempSync('mra-skill-install-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final entry = File('bin/marionette_agent.dart').absolute.path;
    final source = Directory.current.path;
    var destination = Directory(p.join(temp.path, 'bin with spaces'))
      ..createSync();
    Future<ProcessResult> product(List<String> args, {bool compiled = false}) =>
        Process.run(
          compiled
              ? p.join(destination.path, 'marionette-agent')
              : Platform.resolvedExecutable,
          [if (!compiled) entry, ...args],
          workingDirectory: temp.path,
          environment: {
            'MARIONETTE_AGENT_SKILLS_DIR': p.join(temp.path, 'absent'),
          },
        );
    Map body(ProcessResult result, {int code = 0}) {
      expect(
        result.exitCode,
        code,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(result.stderr, isEmpty);
      return jsonDecode(result.stdout as String) as Map;
    }

    final installed = body(
      await product([
        'install',
        '--source',
        source,
        destination.path,
        '--timeout',
        '120000',
        '--json',
      ]),
    );
    expect(installed['ok'], true);
    final original = body(
      await product([
        'skills',
        'get',
        '--all',
        '--full',
        '--json',
      ], compiled: true),
    );
    expect((original['data'] as List).map((s) => s['name']), [
      'core',
      'simulator-verify',
    ]);
    final oldPath =
        body(
              await product([
                'skills',
                'path',
                'core',
                '--json',
              ], compiled: true),
            )['data']['path']
            as String;
    expect(p.isWithin(destination.path, oldPath), true);
    expect(
      File(p.join(oldPath, 'SKILL.md')).readAsStringSync(),
      File('skill-data/core/SKILL.md').readAsStringSync(),
    );
    body(
      await product([
        'install',
        '--source',
        source,
        destination.path,
        '--json',
      ]),
      code: 1,
    );
    expect(
      body(
        await product([
          'skills',
          'get',
          '--all',
          '--full',
          '--json',
        ], compiled: true),
      ),
      original,
    );

    // A malformed source must not replace the existing executable or leave a bundle.
    final badSource = Directory(p.join(temp.path, 'incomplete'))..createSync();
    Directory(p.join(badSource.path, 'bin')).createSync();
    File(p.join(badSource.path, 'pubspec.yaml'))
        .writeAsStringSync('name: marionette_agent\n');
    File(p.join(badSource.path, 'bin/marionette_agent.dart'))
        .writeAsStringSync('void main() {}');
    final before = destination.listSync().map((e) => e.path).toSet();
    final failed = await product([
      'upgrade',
      '--source',
      badSource.path,
      destination.path,
      '--json',
    ]);
    expect(failed.exitCode, isNot(0));
    expect(destination.listSync().map((e) => e.path).toSet(), before);
    expect(
      body(
        await product([
          'skills',
          'get',
          '--all',
          '--full',
          '--json',
        ], compiled: true),
      ),
      original,
    );

    body(
      await product([
        'upgrade',
        '--source',
        source,
        destination.path,
        '--timeout',
        '120000',
        '--json',
      ]),
    );
    final newPath =
        body(
              await product([
                'skills',
                'path',
                'core',
                '--json',
              ], compiled: true),
            )['data']['path']
            as String;
    expect(newPath, isNot(oldPath));
    expect(Directory(oldPath).existsSync(), true);
    destination = destination.renameSync(p.join(temp.path, 'relocated'));
    expect(
      body(
        await product([
          'skills',
          'get',
          '--all',
          '--full',
          '--json',
        ], compiled: true),
      ),
      original,
    );
    final relocated =
        body(
              await product([
                'skills',
                'path',
                'core',
                '--json',
              ], compiled: true),
            )['data']['path']
            as String;
    expect(p.isWithin(destination.path, relocated), true);
    Directory(p.dirname(p.dirname(relocated)))
        .renameSync(p.join(temp.path, 'removed-bundle'));
    final missing = body(
      await product(['skills', 'path', '--json'], compiled: true),
      code: 1,
    );
    expect(missing['error'], contains('Skills directory not found'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
