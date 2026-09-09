import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/marionette_agent.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final png = base64Encode(image.encodePng(image.Image(width: 2, height: 2)));
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('artifact-test-');
  });
  tearDown(() => directory.delete(recursive: true));
  Future<Json> save(List<Object?> values, [String? path]) => saveScreenshots(
    {'images': values},
    path,
    DateTime.now().add(const Duration(seconds: 10)),
  );
  test('valid PNG saves exact bytes and absolute path', () async {
    final path = p.join(directory.path, 'screen.png');
    final result = await save([png], p.relative(path));
    expect(result['paths'], [p.normalize(p.absolute(path))]);
    expect(await File(path).readAsBytes(), base64Decode(png));
  });
  test('temporary output is a valid PNG and uses an absolute path', () async {
    final result = await save([png]);
    final file = File((result['paths'] as List).single as String);
    expect(p.isAbsolute(file.path), true);
    expect(image.decodePng(await file.readAsBytes())!.width, 2);
    await file.parent.delete(recursive: true);
  });
  test('multiple images use numbered paths', () async {
    final result = await save([png, png], p.join(directory.path, 'screen.png'));
    expect(result['paths'], [
      p.join(directory.path, 'screen-1.png'),
      p.join(directory.path, 'screen-2.png'),
    ]);
  });
  test(
    'existing batch destination is rejected before publication',
    () async {
      final existing = File(p.join(directory.path, 'screen-2.png'));
      await existing.writeAsString('keep');
      await expectLater(
        save([png, png], p.join(directory.path, 'screen.png')),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
      expect(await existing.readAsString(), 'keep');
      expect(File(p.join(directory.path, 'screen-1.png')).existsSync(), false);
      await expectLater(save([png], existing.path), throwsA(isA<AgentError>()));
      expect(await existing.readAsString(), 'keep');
    },
  );
  test(
    'empty, malformed, non-PNG and truncated payloads fail before writing',
    () async {
      for (final values in <List<Object?>>[
        [],
        [42],
        ['bad'],
        [
          base64Encode([1, 2, 3]),
        ],
        [png, base64Encode(base64Decode(png).take(12).toList())],
      ]) {
        await expectLater(
          save(values, p.join(directory.path, 'bad.png')),
          throwsA(
            isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR'),
          ),
        );
      }
      expect(directory.listSync(), isEmpty);
    },
  );
  test('write failures and expired deadlines are classified', () async {
    await expectLater(
      save([png], p.join(directory.path, 'missing', 'screen.png')),
      throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
    );
    await expectLater(save([png], directory.path), throwsA(isA<AgentError>()));
    await expectLater(
      saveScreenshots(
        {
          'images': [png],
        },
        p.join(directory.path, 'screen.png'),
        DateTime.now().subtract(const Duration(seconds: 1)),
      ),
      throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
    expect(directory.listSync(), isEmpty);
  });
}
