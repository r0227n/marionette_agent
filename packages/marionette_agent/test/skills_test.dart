import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/skills_command.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  Directory dir(String name) => Directory(p.join(temp.path, name));
  File file(String name) => File(p.join(temp.path, name));
  void write(String path, String content) {
    file(path).parent.createSync(recursive: true);
    file(path).writeAsStringSync(content);
  }

  void skill(String path, String name, {bool hidden = false}) => write(
    '$path/SKILL.md',
    '---\nname: $name\ndescription: $name guide\n  continued description\nhidden: $hidden\n---\n\n# $name\n',
  );

  setUp(() => temp = Directory.systemTemp.createTempSync('mra-skills-'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('all command forms, option placement, and local help', () {
    final parser = CliParser(environment: {});
    for (final args in [
      <String>[],
      ['list'],
    ]) {
      expect(parser.parse(['skills', ...args]).params, {'action': 'list'});
    }
    for (final args in [
      ['skills', 'get', 'core', 'simulator-verify', '--full', '--json'],
      ['--json', 'skills', 'get', '--full', 'core', 'simulator-verify'],
    ]) {
      final invocation = parser.parse(args);
      expect(invocation.resultSession, isNull);
      expect(invocation.json, isTrue);
      expect(invocation.params, {
        'action': 'get',
        'names': ['core', 'simulator-verify'],
        'all': false,
        'full': true,
      });
    }
    expect(
      parser.parse(['skills', 'get', '--all', '--full']).params['all'],
      true,
    );
    expect(parser.parse(['skills', 'path']).params, {
      'action': 'path',
      'name': null,
    });
    expect(parser.parse(['skills', 'path', 'core']).params['name'], 'core');
    expect(parser.parse(['skills', 'get', '--help']).params, {
      'action': 'help',
    });
    for (final args in [
      ['get'],
      ['missing'],
      ['path', 'a', 'b'],
      ['list', '--full'],
      ['get', 'core', '--full', '--full'],
      ['list', 'extra'],
    ]) {
      expect(
        () => parser.parse(['skills', ...args]),
        throwsA(isA<AgentError>()),
      );
    }
  });

  test(
    'existing override replaces bundled search, invalid override falls back',
    () async {
      skill('package/skills/stub', 'stub');
      skill('package/skill-data/core', 'core');
      dir('override').createSync();
      final executable = p.join(temp.path, 'package/bin/cli');
      expect(
        (await findSkillsDirectories(
          executable: executable,
          resolvePackage: false,
          environment: {'MARIONETTE_AGENT_SKILLS_DIR': dir('override').path},
        )).map((d) => d.path),
        [dir('override').path],
      );
      for (final environment in [
        <String, String>{},
        {'MARIONETTE_AGENT_SKILLS_DIR': dir('missing').path},
      ]) {
        expect(
          (await findSkillsDirectories(
            executable: executable,
            resolvePackage: false,
            environment: environment,
          )).map((d) => d.path),
          [dir('package/skills').path, dir('package/skill-data').path],
        );
      }
    },
  );

  test('deep build, symlink, package URI and versioned installation resolve assets', () async {
    skill('package/skills/stub', 'stub');
    skill('package/skill-data/core', 'core');
    write('package/bin/cli', 'fixture');
    Link(file('alias').path).createSync(file('package/bin/cli').path);
    for (final executable in [
      file('package/target/debug/cli').path,
      file('alias').path,
    ]) {
      final result = await findSkillsDirectories(
        executable: executable,
        resolvePackage: false,
        environment: {},
      );
      expect(result.map((d) => d.resolveSymbolicLinksSync()), [
        dir('package/skills').resolveSymbolicLinksSync(),
        dir('package/skill-data').resolveSymbolicLinksSync(),
      ]);
    }
    expect(
      (await findSkillsDirectories(
        executable: file('sdk/bin/dart').path,
        resolvePackage: false,
        environment: {},
        packageUri: file('package/lib/marionette_agent.dart').uri,
      )).map((d) => d.path),
      [dir('package/skills').path, dir('package/skill-data').path],
    );
    expect(
      (await findSkillsDirectories(
        executable: file('cli').path,
        resolvePackage: false,
        environment: {},
        bundle: 'package',
      )).map((d) => d.path),
      [dir('package/skills').path, dir('package/skill-data').path],
    );
    expect(
      await findSkillsDirectories(
        executable: file('cli').path,
        resolvePackage: false,
        environment: {},
      ),
      isEmpty,
    );
    // A missing versioned bundle must not silently load a different version.
    expect(
      await findSkillsDirectories(
        executable: file('package/bin/cli').path,
        resolvePackage: false,
        environment: {},
        bundle: 'absent',
      ),
      isEmpty,
    );
  });

  test('discovery parses metadata, sorts, skips malformed entries and filters hidden', () {
    skill('skills/stub', 'stub', hidden: true);
    skill('skill-data/b', 'beta');
    skill('skill-data/a', 'alpha');
    write('skill-data/invalid/SKILL.md', '# Missing frontmatter');
    write(
      'skill-data/no-name/SKILL.md',
      '---\ndescription: absent name\n---\n',
    );
    write('skill-data/invalid-utf8/SKILL.md', 'placeholder');
    file('skill-data/invalid-utf8/SKILL.md').writeAsBytesSync([0xff]);
    write('skill-data/not-a-skill.txt', 'ignored');
    final catalog = SkillCatalog([dir('skills'), dir('skill-data')]);
    expect(catalog.discover().map((s) => s.name), ['alpha', 'beta', 'stub']);
    final result = catalog.run({'action': 'list'});
    expect(result.data, [
      {'name': 'alpha', 'description': 'alpha guide continued description'},
      {'name': 'beta', 'description': 'beta guide continued description'},
    ]);
    expect(result.text, isNot(contains('stub')));
    expect(
      catalog.run({
        'action': 'get',
        'names': ['stub'],
      }).text,
      contains('hidden: true'),
    );
    expect(
      catalog.run({'action': 'get', 'all': true}).text,
      isNot(contains('# stub')),
    );
    expect(
      parseSkill(dir('x'), '---\nname: x\nhidden: yes\n---')!.hidden,
      true,
    );
  });

  test(
    'get preserves content, caller order and direct supplementary text files',
    () {
      skill('skills/a', 'alpha');
      skill('skills/b', 'beta');
      write('skills/a/references/z.md', 'last');
      write('skills/a/references/a.md', 'first\n');
      write('skills/a/references/nested/ignored.md', 'nested');
      write('skills/a/templates/run.sh', '#!/bin/sh\n');
      file('skills/a/references/binary').writeAsBytesSync([0xff]);
      final catalog = SkillCatalog([dir('skills')]);
      final short = catalog.run({
        'action': 'get',
        'names': ['alpha'],
      });
      expect(short.text, file('skills/a/SKILL.md').readAsStringSync());
      expect((short.data as List).single, isNot(contains('files')));
      final full = catalog.run({
        'action': 'get',
        'names': ['beta', 'alpha'],
        'full': true,
      });
      final items = full.data as List;
      expect(items.map((item) => item['name']), ['beta', 'alpha']);
      expect(items[1]['files'], [
        {'path': 'references/a.md', 'content': 'first\n'},
        {'path': 'references/z.md', 'content': 'last'},
        {'path': 'templates/run.sh', 'content': '#!/bin/sh\n'},
      ]);
      expect(full.text, contains('\n--- references/a.md ---\n\nfirst\n'));
      expect(full.text, isNot(contains('nested')));
      expect(jsonDecode(full.render(true)), {'success': true, 'data': items});
      expect(catalog.run({'action': 'path', 'name': 'alpha'}).data, {
        'name': 'alpha',
        'path': dir('skills/a').path,
      });
      expect(catalog.run({'action': 'path'}).data, {
        'paths': [dir('skills').path],
      });
    },
  );

  test(
    'duplicate names retain search precedence and long Unicode stays valid',
    () {
      skill('skills/a', 'same', hidden: true);
      skill('skill-data/b', 'same');
      write(
        'skill-data/unicode/SKILL.md',
        '---\nname: unicode\ndescription: ${'日本語' * 40}\n---\n',
      );
      final catalog = SkillCatalog([dir('skills'), dir('skill-data')]);
      expect(catalog.discover().map((s) => s.name), [
        'same',
        'same',
        'unicode',
      ]);
      expect(
        catalog.run({
          'action': 'get',
          'names': ['same'],
        }).text,
        contains('hidden: true'),
      );
      final list = catalog.run({'action': 'list'});
      expect(list.text, contains('...'));
      expect(list.text, isNot(contains('\uFFFD')));
      expect((list.data as List).last['description'], '日本語' * 40);
      expect(
        catalog.run({
          'action': 'get',
          'all': true,
          'names': ['missing'],
        }).data,
        hasLength(2),
      );
    },
  );

  test(
    'empty catalog, unknown names, and deadline fail without partial content',
    () {
      dir('skills').createSync();
      final catalog = SkillCatalog([dir('skills')]);
      expect(catalog.run({'action': 'list'}).data, isEmpty);
      expect(catalog.run({'action': 'list'}).text, 'No skills found');
      for (final params in [
        {'action': 'get', 'all': true},
        {
          'action': 'get',
          'names': ['missing'],
        },
        {'action': 'path', 'name': '../escape'},
      ]) {
        expect(() => catalog.run(params), throwsA(isA<AgentError>()));
      }
      expect(
        () => SkillCatalog([]).run({'action': 'list'}),
        throwsA(isA<AgentError>()),
      );
      expect(
        () => SkillCatalog([
          dir('skills'),
        ], deadline: DateTime(2000)).run({'action': 'list'}),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
    },
  );

  group('product CLI', () {
    final script = File('bin/marionette_agent.dart').absolute.path;
    Future<ProcessResult> cli(
      List<String> args, {
      Map<String, String> env = const {},
    }) => Process.run(
      Platform.resolvedExecutable,
      [script, ...args],
      workingDirectory: temp.path,
      environment: {
        'MARIONETTE_AGENT_RUNTIME_DIR': dir('runtime').path,
        'MARIONETTE_AGENT_SKILLS_DIR': dir('absent').path,
        ...env,
      },
    );

    test('bundled commands run outside checkout with no runtime, policy, restore or daemon', () async {
      for (final args in [
        ['skills'],
        ['skills', 'list'],
        ['skills', 'path'],
        ['skills', 'path', 'core'],
        ['skills', 'get', 'core', 'simulator-verify'],
        ['skills', 'get', '--all', '--full'],
        ['skills', '--help'],
        ['skills', 'get', 'marionette-agent'],
      ]) {
        final result = await cli([
          ...args,
          '--json',
          '--restore',
          'absent',
          '--action-policy',
          'absent',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(jsonDecode(result.stdout as String)['success'], true);
        expect(dir('runtime').existsSync(), false);
      }
      final result = await cli(['skills', 'get', 'core']);
      expect(
        result.stdout,
        File('skill-data/core/SKILL.md').readAsStringSync(),
      );
      expect(result.exitCode, 0);
    });

    test('JSON errors are single objects, text errors use stderr, debug is isolated', () async {
      for (final args in [
        ['skills', 'get'],
        ['skills', 'get', 'core', 'missing'],
        ['skills', 'path', 'missing'],
        ['skills', 'missing'],
        ['skills', 'list', '--bad'],
      ]) {
        final result = await cli([...args, '--json']);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        final body = jsonDecode(result.stdout as String) as Map;
        expect(body.keys, unorderedEquals(['success', 'error']));
        expect(body['success'], false);
        expect(body['error'], isA<String>());
      }
      final text = await cli(['skills', 'get', 'missing']);
      expect(text.exitCode, 1);
      expect(text.stdout, isEmpty);
      expect(text.stderr, contains('Skill not found: missing'));
      final debug = await cli(['skills', 'list', '--debug', '--json']);
      expect(debug.exitCode, 0);
      expect(jsonDecode(debug.stdout as String)['success'], true);
      expect(debug.stderr, contains('cliResult'));
      expect(debug.stderr, isNot(contains('runtimePrepare')));
      expect(dir('runtime').existsSync(), false);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
