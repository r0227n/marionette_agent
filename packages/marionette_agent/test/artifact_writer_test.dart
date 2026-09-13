import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
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
  test('existing batch destination is rejected before publication', () async {
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
  });
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
    final existingDirectory = await Directory(p.join(directory.path, 'dir.png'))
        .create();
    await expectLater(
      save([png], existingDirectory.path),
      throwsA(isA<AgentError>()),
    );
    await existingDirectory.delete();
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

  Future<Json> jpeg(List<String> payloads, String? path, {int quality = 90}) =>
      saveScreenshots(
        {'images': payloads},
        path,
        DateTime.now().add(const Duration(seconds: 10)),
        format: ScreenshotFormat.jpeg,
        quality: quality,
      );

  test(
    'JPEG preserves dimensions and applies 0, custom, default and 100 quality',
    () async {
      final fixture = image.Image(width: 31, height: 19);
      for (final pixel in fixture) {
        pixel.setRgb(
          (pixel.x * 31) % 256,
          (pixel.y * 47) % 256,
          (pixel.x * pixel.y * 13) % 256,
        );
      }
      final payload = base64Encode(image.encodePng(fixture));
      final outputs = <int, List<int>>{};
      for (final quality in [0, 37, 90, 100]) {
        final path = p.join(directory.path, 'q$quality.jpeg');
        final result = await jpeg([payload], path, quality: quality);
        expect(result['paths'], [path]);
        final bytes = await File(path).readAsBytes();
        expect(bytes.take(2), [0xff, 0xd8]);
        final decoded = image.decodeJpg(bytes)!;
        expect(
          [decoded.width, decoded.height, decoded.numChannels],
          [31, 19, 3],
        );
        // Compare with the pinned encoder's public API, including its 0 -> 1 floor.
        expect(bytes, image.encodeJpg(fixture, quality: quality));
        outputs[quality] = bytes;
      }
      expect(outputs[0], isNot(outputs[37]));
      expect(outputs[37], isNot(outputs[90]));
      expect(outputs[90], isNot(outputs[100]));
      final result = await jpeg([payload], null);
      final file = File((result['paths'] as List).single as String);
      try {
        expect(p.isAbsolute(file.path), isTrue);
        expect(p.basename(file.path), 'screen.jpg');
        expect(await file.readAsBytes(), outputs[90]);
      } finally {
        await file.parent.delete(recursive: true);
      }
    },
  );

  test('PNG retains transparency; JPEG composites transparent and partial alpha over white', () async {
    for (final channels in [2, 4]) {
      for (final alpha in [0, 128, 255]) {
        // Non-block dimensions also check the repeatedly padded JPEG edge.
        final fixture = image.Image(
          width: 13,
          height: 11,
          numChannels: channels,
        );
        for (final pixel in fixture) {
          pixel.a = alpha;
        }
        final payload = base64Encode(image.encodePng(fixture));
        final stem = p.join(directory.path, 'alpha-$channels-$alpha');
        await save([payload], '$stem.png');
        final original = await File('$stem.png').readAsBytes();
        expect(original, base64Decode(payload));
        expect(image.decodePng(original)!.getPixel(0, 0).a, alpha);
        await jpeg([payload], '$stem.jpg', quality: 100);
        final converted = image.decodeJpg(
          await File('$stem.jpg').readAsBytes(),
        )!;
        expect([converted.width, converted.height], [13, 11]);
        for (final pixel in converted) {
          expect(pixel.r, closeTo(255 - alpha, 2));
          expect(pixel.g, closeTo(255 - alpha, 2));
          expect(pixel.b, closeTo(255 - alpha, 2));
          expect(pixel.a, 255);
        }
      }
    }
  });

  test(
    '16-bit and palette PNG alpha also produces opaque white JPEG',
    () async {
      for (final fixture in [
        image.Image(
          width: 3,
          height: 5,
          numChannels: 4,
          format: image.Format.uint16,
        ),
        image.Image(width: 3, height: 5, numChannels: 4, withPalette: true),
      ]) {
        final result = await jpeg(
          [base64Encode(image.encodePng(fixture))],
          null,
          quality: 100,
        );
        final file = File((result['paths'] as List).single as String);
        try {
          final decoded = image.decodeJpg(await file.readAsBytes())!;
          expect([decoded.width, decoded.height], [3, 5]);
          for (final pixel in decoded) {
            expect([pixel.r, pixel.g, pixel.b, pixel.a], [255, 255, 255, 255]);
          }
        } finally {
          await file.parent.delete(recursive: true);
        }
      }
    },
  );

  test(
    'opaque grayscale stays neutral and partial color alpha uses a white matte',
    () async {
      final gray = image.Image(width: 9, height: 7, numChannels: 1);
      for (final pixel in gray) {
        pixel.r = 80;
      }
      final color = image.Image(width: 9, height: 7, numChannels: 4);
      for (final pixel in color) {
        pixel.setRgba(255, 0, 0, 128);
      }
      for (final entry in {
        gray: [80, 80, 80],
        color: [255, 127, 127],
      }.entries) {
        final result = await jpeg(
          [base64Encode(image.encodePng(entry.key))],
          null,
          quality: 100,
        );
        final file = File((result['paths'] as List).single as String);
        try {
          for (final pixel in image.decodeJpg(await file.readAsBytes())!) {
            expect(pixel.r, closeTo(entry.value[0], 2));
            expect(pixel.g, closeTo(entry.value[1], 2));
            expect(pixel.b, closeTo(entry.value[2], 2));
          }
        } finally {
          await file.parent.delete(recursive: true);
        }
      }
    },
  );

  test(
    'extensionless destinations and multiple JPEGs use selected extension',
    () async {
      final base = p.join(directory.path, 'screen');
      expect((await save([png], base))['paths'], ['$base.png']);
      expect((await jpeg([png], base))['paths'], ['$base.jpg']);
      expect((await jpeg([png, png], '$base.JPEG'))['paths'], [
        '$base-1.JPEG',
        '$base-2.JPEG',
      ]);
      final result = await jpeg([png, png], null);
      final paths = (result['paths'] as List).cast<String>();
      try {
        expect(paths.map(p.basename), ['screen-1.jpg', 'screen-2.jpg']);
        for (final path in paths) {
          expect(image.decodeJpg(await File(path).readAsBytes()), isNotNull);
        }
      } finally {
        await File(paths.first).parent.delete(recursive: true);
      }
    },
  );

  test('JPEG batches refuse existing files, directories and live/dangling symlinks', () async {
    final base = p.join(directory.path, 'screen');
    final target = File(p.join(directory.path, 'target'))
      ..writeAsStringSync('keep');
    for (final kind in ['file', 'directory', 'link', 'dangling']) {
      final occupied = '$base-2.jpg';
      switch (kind) {
        case 'file':
          File(occupied).writeAsStringSync('existing');
        case 'directory':
          Directory(occupied).createSync();
        case 'link':
          Link(occupied).createSync(target.path);
        case 'dangling':
          Link(occupied).createSync('${target.path}-missing');
      }
      await expectLater(
        jpeg([png, png], '$base.jpg'),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
      expect(File('$base-1.jpg').existsSync(), isFalse);
      expect(target.readAsStringSync(), 'keep');
      expect(File('${target.path}-missing').existsSync(), isFalse);
      if (kind == 'file') expect(File(occupied).readAsStringSync(), 'existing');
      switch (kind) {
        case 'file':
          File(occupied).deleteSync();
        case 'directory':
          Directory(occupied).deleteSync();
        case 'link' || 'dangling':
          Link(occupied).deleteSync();
      }
    }
  });

  test('bad later PNG in a JPEG batch leaves no partial output', () async {
    await expectLater(
      jpeg([png, 'not-png'], p.join(directory.path, 'screen.jpg')),
      throwsA(isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR')),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('conversion consumes the original deadline before reserving destinations', () async {
    final start = DateTime.utc(2026);
    var checks = 0;
    await expectLater(
      saveScreenshots(
        {
          'images': [png],
        },
        p.join(directory.path, 'late.jpg'),
        start.add(const Duration(milliseconds: 6)),
        format: ScreenshotFormat.jpeg,
        // Advance only at checkpoints: start, decode start/end, composite row,
        // composite end, JPEG end. No wall-clock load or slow fixture required.
        now: () => start.add(Duration(milliseconds: ++checks)),
      ),
      throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
    expect(checks, 6);
    expect(directory.listSync(), isEmpty);
  });

  for (final afterWrite in [false, true]) {
    test(
      'deadline after ${afterWrite ? 'writing' : 'reserving'} a JPEG cleans all owned artifacts',
      () async {
        final before = DateTime.utc(2026);
        final deadline = before.add(const Duration(seconds: 1));
        final first = File(p.join(directory.path, 'screen-1.jpg'));
        final keep = File(p.join(directory.path, 'keep.jpg'))
          ..writeAsStringSync('keep');
        await expectLater(
          saveScreenshots(
            {
              'images': [png, png],
            },
            p.join(directory.path, 'screen.jpg'),
            deadline,
            format: ScreenshotFormat.jpeg,
            now: () =>
                first.existsSync() && (!afterWrite || first.lengthSync() > 0)
                ? deadline
                : before,
          ),
          throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
        );
        expect(directory.listSync().map((f) => f.path), [keep.path]);
        expect(keep.readAsStringSync(), 'keep');
      },
    );
  }
}
