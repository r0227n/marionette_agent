import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final png = base64Encode(image.encodePng(image.Image(width: 2, height: 2)));
  final secondPng = base64Encode(
    image.encodePng(image.Image(width: 3, height: 1)),
  );
  final ioError = throwsA(
    isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR'),
  );
  late Directory root;
  late Directory output;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('screenshot-dir-test-');
    output = await Directory(p.join(root.path, 'images')).create();
  });
  tearDown(() => root.delete(recursive: true));

  Future<Json> save({String? path, String? directory, List<String>? images}) =>
      saveScreenshots(
        {
          'images': images ?? [png],
        },
        path,
        DateTime.now().add(const Duration(seconds: 10)),
        screenshotDir: directory ?? output.path,
      );

  test(
    'relative directory saves directly inside it with an absolute path',
    () async {
      final result = await save(directory: p.relative(output.path));
      final path = (result['paths'] as List).single as String;
      expect(p.isAbsolute(path), isTrue);
      expect(p.dirname(path), p.normalize(p.absolute(output.path)));
      expect(p.basename(path), matches(r'^screen-[0-9a-f]{32}\.png$'));
      expect(await File(path).readAsBytes(), base64Decode(png));
    },
  );

  test(
    'explicit path wins without inspecting or creating the directory',
    () async {
      final missing = p.join(root.path, 'missing');
      final path = p.join(root.path, 'explicit.png');
      final result = await save(path: p.relative(path), directory: missing);
      expect(result['paths'], [p.normalize(p.absolute(path))]);
      expect(await File(path).readAsBytes(), base64Decode(png));
      expect(Directory(missing).existsSync(), isFalse);
      expect(output.listSync(), isEmpty);
    },
  );

  test(
    'parallel batches have distinct names and preserve every image in order',
    () async {
      final sentinel = File(p.join(output.path, 'existing.png'));
      await sentinel.writeAsString('keep');
      final batches = await Future.wait(
        List.generate(16, (_) => save(images: [png, secondPng])),
      );
      final allPaths = <String>[];
      for (final batch in batches) {
        final paths = (batch['paths'] as List).cast<String>();
        expect(paths, hasLength(2));
        expect(paths[0], endsWith('-1.png'));
        expect(paths[1], paths[0].replaceFirst('-1.png', '-2.png'));
        expect(await File(paths[0]).readAsBytes(), base64Decode(png));
        expect(await File(paths[1]).readAsBytes(), base64Decode(secondPng));
        expect(paths.every(p.isAbsolute), isTrue);
        expect(paths.every((path) => p.dirname(path) == output.path), isTrue);
        allPaths.addAll(paths);
      }
      expect(allPaths.toSet(), hasLength(32));
      expect(output.listSync(), hasLength(33));
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test(
    'simultaneous explicit path claims never overwrite the winning image',
    () async {
      final path = p.join(root.path, 'race.png');
      final results = await Future.wait([
        for (final bytes in [png, secondPng])
          save(
            path: path,
            images: [bytes],
          ).then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(results.whereType<AgentError>().single.code, 'IO_ERROR');
      expect(results.whereType<Json>(), hasLength(1));
      final winner = results.first is AgentError ? secondPng : png;
      expect(await File(path).readAsBytes(), base64Decode(winner));
    },
  );

  test(
    'missing directories and regular files fail without being replaced',
    () async {
      final missing = p.join(root.path, 'missing', 'nested');
      await expectLater(save(directory: missing), ioError);
      expect(Directory(p.dirname(missing)).existsSync(), isFalse);
      final file = File(p.join(root.path, 'file'));
      await file.writeAsString('keep');
      await expectLater(save(directory: file.path), ioError);
      expect(await file.readAsString(), 'keep');
    },
  );

  test(
    'directory symlinks including trailing separators are refused',
    () async {
      final link = await Link(p.join(root.path, 'linked')).create(output.path);
      for (final suffix in ['', '/', '/.']) {
        await expectLater(save(directory: '${link.path}$suffix'), ioError);
      }
      expect(await link.target(), output.path);
      expect(output.listSync(), isEmpty);
      await link.delete();
      final missing = p.join(root.path, 'missing');
      await link.create(missing);
      await expectLater(save(directory: link.path), ioError);
      expect(await link.target(), missing);
      expect(Directory(missing).existsSync(), isFalse);
    },
  );

  test('batch reservation failure removes only this request files', () async {
    final target = File(p.join(root.path, 'keep.png'));
    await target.writeAsString('keep');
    final existing = p.join(output.path, 'batch-2.png');
    final link = await Link(existing).create(target.path);
    await expectLater(
      save(path: p.join(output.path, 'batch.png'), images: [png, secondPng]),
      ioError,
    );
    expect(File(p.join(output.path, 'batch-1.png')).existsSync(), isFalse);
    expect(await link.target(), target.path);
    expect(await target.readAsString(), 'keep');
    await expectLater(save(path: link.path), ioError);
    expect(await target.readAsString(), 'keep');
    await link.delete();
    await Directory(existing).create();
    await expectLater(
      save(path: p.join(output.path, 'batch.png'), images: [png, secondPng]),
      ioError,
    );
    expect(output.listSync().single.path, existing);
    expect(Directory(existing).existsSync(), isTrue);
  });

  test('permission failure is IO_ERROR and leaves no batch files', () async {
    final chmod = await Process.run('chmod', ['500', output.path]);
    expect(chmod.exitCode, 0);
    try {
      await expectLater(save(images: [png, secondPng]), ioError);
      expect(output.listSync(), isEmpty);
    } finally {
      final restore = await Process.run('chmod', ['700', output.path]);
      expect(restore.exitCode, 0);
    }
  });

  test('invalid batches and expired deadlines create no files', () async {
    for (final images in <List<String>>[
      [],
      [png, 'bad'],
    ]) {
      await expectLater(
        save(images: images),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR'),
        ),
      );
    }
    await expectLater(
      saveScreenshots(
        {
          'images': [png],
        },
        null,
        DateTime.now().subtract(const Duration(seconds: 1)),
        screenshotDir: output.path,
      ),
      throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
    expect(output.listSync(), isEmpty);
  });
}
