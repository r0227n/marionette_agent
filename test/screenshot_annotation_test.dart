import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

Json geometry({int width = 400, int height = 600, double scale = 2}) => {
  'version': 1,
  'viewCount': 1,
  'viewId': '0',
  'rotation': 0,
  'originX': 0,
  'originY': 0,
  'pixelWidth': width,
  'pixelHeight': height,
  'logicalWidth': width / scale,
  'logicalHeight': height / scale,
};

Json target(String ref, [Json? bounds]) => {
  'ref': ref,
  'bounds': bounds ?? {'x': 20, 'y': 30, 'width': 40, 'height': 50},
};

class MappedFake extends FakeBackend implements MappedScreenshotBackend {
  Future<void> Function()? onCapture;
  @override
  Future<MappedScreenshot> captureMappedScreenshot() async {
    await onCapture?.call();
    return MappedScreenshot('encoded', ScreenshotGeometry.decode(geometry()));
  }
}

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('i11-test-'),
  );
  tearDown(() => directory.delete(recursive: true));
  Future<Json> save(
    Json g,
    List<Json> targets, {
    List<String>? payloads,
    String name = 'annotated.png',
    DateTime? deadline,
  }) {
    final original = img.Image(width: 400, height: 600);
    img.fill(original, color: img.ColorRgb8(255, 255, 255));
    return saveScreenshots(
      {
        'images': payloads ?? [base64Encode(img.encodePng(original))],
        'geometry': g,
        'annotations': {'generation': 7, 'targets': targets},
      },
      '${directory.path}/$name',
      deadline ?? DateTime.now().add(const Duration(seconds: 10)),
    );
  }

  test(
    'JPEG encodes annotated pixels and preserves annotation metadata',
    () async {
      final original = img.Image(width: 400, height: 600);
      img.fill(original, color: img.ColorRgb8(255, 255, 255));
      final result = await saveScreenshots(
        {
          'images': [base64Encode(img.encodePng(original))],
          'geometry': geometry(),
          'annotations': {
            'generation': 7,
            'targets': [target('@e1')],
          },
        },
        null,
        DateTime.now().add(const Duration(seconds: 10)),
        screenshotDir: directory.path,
        format: ScreenshotFormat.jpeg,
        quality: 100,
      );
      final path = (result['paths'] as List).single as String;
      expect(File(path).parent.path, directory.path);
      expect(path.split('/').last, matches(r'^screen-[0-9a-f]{32}\.jpg$'));
      expect(result['annotated'], isTrue);
      expect(result['annotationCount'], 1);
      expect(result['generation'], 7);
      final bytes = await File((result['paths'] as List).single as String)
          .readAsBytes();
      expect(bytes.take(2), [0xff, 0xd8]);
      final output = img.decodeJpg(bytes)!;
      expect([output.width, output.height], [400, 600]);
      final border = output.getPixel(119, 120);
      expect(border.r, greaterThan(180));
      expect(border.g, lessThan(70));
      expect(border.b, lessThan(130));
      final outside = output.getPixel(130, 120);
      expect(outside.r, greaterThan(245));
      expect(outside.g, greaterThan(245));
      expect(outside.b, greaterThan(245));
    },
  );

  test(
    'explicit scale maps borders to exact image pixels without changing source',
    () async {
      for (final scale in [1.0, 2.0, 2.5]) {
        final result = await save(geometry(scale: scale), [
          target('@e1'),
        ], name: '$scale.png');
        expect(result['annotationCount'], 1);
        expect(result['generation'], 7);
        final output = img.decodePng(
          await File((result['paths'] as List).single as String).readAsBytes(),
        )!;
        final border = output.getPixel(
          (60 * scale).ceil() - 1,
          (60 * scale).floor(),
        );
        expect([border.r, border.g, border.b], [220, 25, 80]);
        final outside = output.getPixel(
          (60 * scale).ceil() + 3,
          (60 * scale).floor(),
        );
        expect([outside.r, outside.g, outside.b], [255, 255, 255]);
      }
    },
  );

  test(
    'landscape is explicit geometry; relative image rotations are rejected',
    () async {
      final image = img.Image(width: 600, height: 400);
      expect(
        (await save(
          geometry(width: 600, height: 400),
          [target('@e2')],
          payloads: [base64Encode(img.encodePng(image))],
        ))['annotationCount'],
        1,
      );
      for (final rotation in [90, 180, 270]) {
        await expectLater(
          save(
            {...geometry(), 'rotation': rotation},
            [target('@e1')],
            name: 'rotation.png',
          ),
          throwsA(
            isA<AgentError>().having(
              (e) => e.code,
              'code',
              'UNSUPPORTED_CAPABILITY',
            ),
          ),
        );
      }
    },
  );

  test('overlapping bounds receive separate legible ref labels', () async {
    final result = await save(geometry(), [target('@e1'), target('@e2')]);
    expect(result['annotationCount'], 2);
    final output = img.decodePng(
      await File((result['paths'] as List).single as String).readAsBytes(),
    )!;
    for (final y in [63, 85]) {
      final glyph = output.getPixel(44, y);
      expect([glyph.r, glyph.g, glyph.b], [255, 255, 255]);
      final background = output.getPixel(42, y);
      expect([background.r, background.g, background.b], [220, 25, 80]);
    }
  });

  test('unverified dimensions, origin, view identity and multiple images never save', () async {
    for (final g in <Json>[
      {},
      {...geometry(), 'viewCount': 2},
      {...geometry(), 'viewId': ''},
      {...geometry(), 'pixelWidth': 401},
      {...geometry(), 'originX': 1},
      {...geometry(), 'logicalWidth': double.nan},
    ]) {
      await expectLater(
        save(g, [target('@e1')]),
        throwsA(
          isA<AgentError>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
    }
    final png = base64Encode(img.encodePng(img.Image(width: 400, height: 600)));
    await expectLater(
      save(geometry(), [target('@e1')], payloads: [png, png]),
      throwsA(
        isA<AgentError>().having(
          (e) => e.code,
          'code',
          'UNSUPPORTED_CAPABILITY',
        ),
      ),
    );
    expect(directory.listSync(), isEmpty);
  });

  test(
    'missing and out-of-view bounds are skipped explicitly, not clamped',
    () async {
      final result = await save(geometry(), [
        target('@e1'),
        {'ref': '@e2', 'bounds': null},
        target('@e3', {'x': -1, 'y': 0, 'width': 20, 'height': 20}),
        target('@e4', {'x': 199, 'y': 0, 'width': 20, 'height': 20}),
        target('@e5', {'x': 0, 'y': 0, 'width': 0, 'height': 20}),
      ]);
      expect(result['annotationCount'], 1);
      expect(result['skippedAnnotations'], [
        {'ref': '@e2', 'reason': 'missing_or_invalid_bounds'},
        for (final ref in ['@e3', '@e4', '@e5'])
          {'ref': ref, 'reason': 'bounds_outside_view'},
      ]);
    },
  );

  test(
    'annotated saving preserves existing originals and whole deadline',
    () async {
      final existing = File('${directory.path}/annotated.png');
      await existing.writeAsString('original');
      await expectLater(
        save(geometry(), [target('@e1')]),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
      expect(await existing.readAsString(), 'original');
      await expectLater(
        save(
          geometry(),
          [target('@e1')],
          name: 'timeout.png',
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      expect(directory.listSync().length, 1);
    },
  );

  test('grammar and IPC annotation flag validation', () {
    expect(CliParser().parse(['screenshot', '--annotate', 'copy.png']).params, {
      'annotate': true,
      'path': 'copy.png',
    });
    expect(CliParser().usage, contains('screenshot [--annotate] [path]'));
  });

  group('snapshot lifetime', () {
    late MappedFake backend;
    late SessionManager manager;
    setUp(() async {
      backend = MappedFake()
        ..elements = [
          ElementInfo(
            key: 'button',
            bounds: {'x': 20, 'y': 30, 'width': 40, 'height': 50},
          ),
        ];
      manager = SessionManager(() => backend, coreCommands());
      await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      );
    });
    tearDown(() => manager.dispose());
    Future<Result> annotate() =>
        manager.handle(request('screenshot', params: {'annotate': true}));

    test('annotation does not allocate or invalidate refs; mutations reject stale snapshots', () async {
      expect((await annotate()).error!.code, 'STALE_REF');
      final snapshot = (await manager.handle(request('snapshot'))).data!;
      final result = await annotate();
      expect(result.error, isNull);
      expect(
        (result.data!['annotations'] as Map)['generation'],
        snapshot['generation'],
      );
      final ref = ((snapshot['elements'] as List).single as Map)['ref'];
      expect(
        ((result.data!['annotations'] as Map)['targets'] as List).single,
        target(ref as String),
      );
      expect(
        (await manager.handle(request('tap', params: {'ref': ref}))).error,
        isNull,
      );
      expect((await annotate()).error!.code, 'STALE_REF');
    });

    test(
      'changed attributes before or during capture never publish annotations',
      () async {
        await manager.handle(request('snapshot'));
        backend.elements = [
          ElementInfo(
            key: 'button',
            bounds: {'x': 21, 'y': 30, 'width': 40, 'height': 50},
          ),
        ];
        expect((await annotate()).error!.code, 'STALE_REF');
        await manager.handle(request('snapshot'));
        backend.onCapture = () async => backend.elements = [];
        expect((await annotate()).error!.code, 'STALE_REF');
      },
    );

    test('invalid IPC flag leaves snapshot available', () async {
      await manager.handle(request('snapshot'));
      expect(
        (await manager.handle(
          request('screenshot', params: {'annotate': 'yes'}),
        )).error!.code,
        'INVALID_ARGUMENT',
      );
      expect((await annotate()).error, isNull);
    });

    test(
      'only delivered refs from a limited snapshot can be annotated',
      () async {
        await manager.handle(
          Request(
            requestId: 'limited',
            session: 'a',
            command: 'snapshot',
            params: const {},
            maxOutput: 1,
            deadline: DateTime.now().add(const Duration(seconds: 2)),
          ),
        );
        final result = await annotate();
        expect(result.error, isNull);
        expect((result.data!['annotations'] as Map)['targets'], isEmpty);
      },
    );
  });

  test('backend without capability rejects and leaves refs valid', () async {
    final backend = FakeBackend()..elements = [ElementInfo(key: 'button')];
    final manager = SessionManager(() => backend, coreCommands());
    addTearDown(manager.dispose);
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
    final snapshot = (await manager.handle(request('snapshot'))).data!;
    expect(
      (await manager.handle(request('screenshot', params: {'annotate': true})))
          .error!
          .code,
      'UNSUPPORTED_CAPABILITY',
    );
    final ref = ((snapshot['elements'] as List).single as Map)['ref'];
    expect(
      (await manager.handle(request('tap', params: {'ref': ref}))).error,
      isNull,
    );
  });
}
