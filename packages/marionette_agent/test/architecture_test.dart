import 'dart:io';

import 'package:test/test.dart';

void main() {
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
}
