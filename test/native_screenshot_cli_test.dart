import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const device = '11111111-2222-3333-4444-555555555555';

void main() {
  late Directory root;
  late String runtime;
  final script = File('test/support/fake_cli.dart').absolute.path;
  Future<ProcessResult> cli(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    [script, '--json', '--session=cold', '--timeout=30000', ...args],
    workingDirectory: root.path,
    environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime},
  );
  Map data(ProcessResult result) {
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, isEmpty);
    return (jsonDecode(result.stdout as String) as Map)['data'] as Map;
  }

  setUp(() async {
    root = await Directory('/tmp').createTemp('mra-native-cli-');
    runtime = p.join(root.path, 'runtime');
  });
  tearDown(() async {
    await cli(['close', '--all']);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (File('$runtime/daemon.json').existsSync() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(File('$runtime/daemon.json').existsSync(), isFalse);
    await root.delete(recursive: true);
  });
  for (final mode in ['screenshot', 'workflow', 'diff']) {
    test('$mode starts a cold daemon without connecting to Flutter', () async {
      final path = p.join(root.path, 'proof.png');
      List<String> args;
      if (mode == 'workflow') {
        final file = File(p.join(root.path, 'proof.json'));
        await file.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'name': 'native',
            'steps': [
              {
                'id': 'proof',
                'action': 'screenshot',
                'device': device,
                'path': path,
              },
            ],
          }),
        );
        args = ['workflow', 'run', file.path];
      } else if (mode == 'diff') {
        await File(path)
            .writeAsBytes(image.encodePng(image.Image(width: 1, height: 1)));
        args = ['diff', 'screenshot', '--baseline', path, '--device', device];
      } else {
        args = ['screenshot', path, '--device', device];
      }
      final result = data(await cli(args));
      expect(Directory(runtime).existsSync(), isTrue);
      if (mode == 'screenshot') {
        expect(result['capture']['method'], 'xcuiscreen');
      } else if (mode == 'workflow') {
        expect(result['completedSteps'], 1);
        expect(result['screenshots'][0]['capture']['method'], 'xcuiscreen');
      } else {
        expect(result['changed'], isFalse);
      }
      expect(image.decodePng(await File(path).readAsBytes()), isNotNull);
    });
  }
  test(
    'removed source, annotations and crop targets fail before daemon startup',
    () async {
      for (final args in [
        ['screenshot', '--source=flutter', '--device=$device'],
        ['screenshot', '--annotate', '--device=$device'],
        ['screenshot', '--key=text_input', '--device=$device'],
        ['screenshot', '@e1', '--device=$device'],
        ['screenshot'],
      ]) {
        final result = await cli(args);
        expect(
          result.exitCode,
          2,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          (jsonDecode(result.stdout as String) as Map)['error']['code'],
          'INVALID_ARGUMENT',
        );
        expect(Directory(runtime).existsSync(), isFalse);
        expect(File(p.join(root.path, '@e1')).existsSync(), isFalse);
      }
    },
  );
}
