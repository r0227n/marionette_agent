import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('action policy has no transitive dependency on session execution', () {
    final pending = [File('lib/src/session/action_policy.dart').absolute.uri];
    final visited = <Uri>{};
    while (pending.isNotEmpty) {
      final uri = pending.removeLast();
      if (!visited.add(uri)) continue;
      expect(uri.path, isNot(endsWith('/session/session.dart')));
      expect(uri.path, isNot(endsWith('/commands/command_context.dart')));
      expect(uri.path, isNot(endsWith('/commands/registry.dart')));
      expect(uri.path, isNot(contains('/daemon/')));
      expect(uri.path, isNot(contains('/cli/')));
      final code = File.fromUri(uri).readAsStringSync();
      for (final match in RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(code)) {
        final imported = match[1]!;
        if (imported.startsWith('package:marionette_agent/')) {
          pending.add(
            Directory('lib').absolute.uri.resolve(
              imported.substring('package:marionette_agent/'.length),
            ),
          );
        } else if (!Uri.parse(imported).hasScheme) {
          pending.add(uri.resolve(imported));
        }
      }
    }
  });

  test('daemon modules do not depend on CLI grammar or the public barrel', () {
    for (final module in [
      'backend',
      'commands',
      'daemon',
      'diagnostics',
      'output',
      'protocol',
      'recording',
      'session',
      'snapshot',
      'workflow',
    ]) {
      for (final file in Directory(
        'lib/src/$module',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final imports = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''')
            .allMatches(file.readAsStringSync())
            .map((match) => match[1]!);
        for (final imported in imports) {
          expect(imported, isNot(contains('/cli/')), reason: file.path);
          expect(
            imported,
            isNot(startsWith('package:args/')),
            reason: file.path,
          );
          expect(
            imported,
            isNot('package:marionette_agent/marionette_agent.dart'),
            reason: file.path,
          );
        }
      }
    }
  });
  test('target execution commands stay inside platform packages', () {
    for (final file in Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final code = file.readAsStringSync();
      expect(code, isNot(contains('--web-run-headless')), reason: file.path);
      expect(code, isNot(contains('--vmservice-out-file')), reason: file.path);
      expect(code, isNot(contains('-no-window')), reason: file.path);
      expect(code, isNot(contains('MARIONETTE_HEADLESS=')), reason: file.path);
    }
  });
  test('platform implementations have no reverse or sibling dependencies', () {
    for (final name in [
      'platform_interface',
      'ios',
      'android',
      'macos',
      'web',
      'flutter',
    ]) {
      final root = Directory('packages/marionette_agent_$name');
      final spec = loadYaml(
        File('${root.path}/pubspec.yaml').readAsStringSync(),
      ) as YamlMap;
      final dependencies = spec['dependencies'] as YamlMap?;
      for (final dependency in dependencies?.keys ?? []) {
        expect(dependency, isNot('marionette_agent'), reason: name);
        if ((dependency as String).startsWith('marionette_agent_')) {
          expect(
            dependency,
            'marionette_agent_platform_interface',
            reason: name,
          );
        }
      }
      for (final file in Directory(
        '${root.path}/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in RegExp(
          r'''(?:import|export)\s+['"]([^'"]+)['"]''',
        ).allMatches(file.readAsStringSync())) {
          final imported = match[1]!;
          expect(
            imported,
            isNot(startsWith('package:marionette_agent/')),
            reason: file.path,
          );
          if (imported.startsWith('package:marionette_agent_')) {
            final package = imported.substring(8).split('/').first;
            expect(
              package,
              anyOf(
                'marionette_agent_platform_interface',
                'marionette_agent_$name',
              ),
              reason: file.path,
            );
          }
        }
      }
    }
  });
}
