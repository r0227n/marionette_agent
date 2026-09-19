import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII=',
  );
  late Directory dir;
  late String encoder;
  final target = RecordingTarget(RecordingPlatform.flutter, 'test', fps: 60);
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('png-recorder-test-');
    encoder = '${dir.path}/encoder';
    await File(encoder).writeAsString(r'''#!/bin/sh
if [ "$1" = "-version" ]; then exit 0; fi
for last; do :; done
printf 'encoded fixture' > "$last"
''');
    await Process.run('chmod', ['700', encoder]);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'stop publishes once and preserves observed acquisition timing',
    () async {
      var closed = 0;
      final recording = await PngScreenRecorder(
        capture: () async => png,
        close: () async {
          closed++;
        },
        encoder: encoder,
      ).start(target, '${dir.path}/capture.mp4', deadline());
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await Future.wait([recording.stop(), recording.stop()]);
      expect(closed, 1);
      expect(recording.isRunning, false);
      expect(
        await File('${dir.path}/capture.mp4').readAsString(),
        'encoded fixture',
      );
      final manifest = await File('${dir.path}/frames/frames.ffconcat')
          .readAsString();
      final durations = RegExp(r'duration ([0-9.]+)')
          .allMatches(manifest)
          .map((match) => double.parse(match[1]!))
          .toList();
      expect(durations.length, greaterThanOrEqualTo(2));
      expect(durations.reduce((a, b) => a + b), lessThan(1));
    },
  );

  test('empty capture cannot create a successful blank recording', () async {
    var closed = false;
    await expectLater(
      PngScreenRecorder(
        capture: () async => [],
        close: () async {
          closed = true;
        },
        encoder: encoder,
      ).start(target, '${dir.path}/capture.mp4', deadline()),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
      ),
    );
    expect(closed, true);
    expect(File('${dir.path}/capture.mp4').existsSync(), false);
  });

  test(
    'size changes fail instead of stretching or mixing different views',
    () async {
      var count = 0;
      final changed = Uint8List.fromList(png);
      ByteData.sublistView(changed).setUint32(16, 2);
      final recording = await PngScreenRecorder(
        capture: () async => count++ == 0 ? png : changed,
        close: () async {},
        encoder: encoder,
      ).start(target, '${dir.path}/capture.mp4', deadline());
      await recording.ended.timeout(const Duration(seconds: 2));
      await expectLater(
        recording.stop(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
      expect(File('${dir.path}/capture.mp4').existsSync(), false);
    },
  );

  test(
    'aborting an in-flight capture closes only its feed and never encodes',
    () async {
      final pending = Completer<List<int>>();
      final requested = Completer<void>();
      var count = 0;
      final recording = await PngScreenRecorder(
        capture: () {
          if (count++ == 0) return Future.value(png);
          requested.complete();
          return pending.future;
        },
        close: () async {
          if (!pending.isCompleted) pending.complete(png);
        },
        encoder: encoder,
      ).start(target, '${dir.path}/capture.mp4', deadline());
      await requested.future;
      await recording.abort();
      await expectLater(recording.stop(), throwsA(isA<PlatformException>()));
      expect(recording.isRunning, false);
      expect(File('${dir.path}/capture.mp4').existsSync(), false);
    },
  );

  test('encoder failure is not published by the recording manager', () async {
    await File(encoder).writeAsString(r'''#!/bin/sh
if [ "$1" = "-version" ]; then exit 0; fi
echo private-encoder-message >&2
exit 9
''');
    final manager = RecordingManager();
    addTearDown(manager.dispose);
    await manager.start(
      owner: 'test',
      target: target,
      path: '${dir.path}/result.mp4',
      deadline: deadline(),
      recorder: PngScreenRecorder(
        capture: () async => png,
        close: () async {},
        encoder: encoder,
      ),
    );
    await expectLater(
      manager.stop('test', deadline()),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          isNot(contains('private-encoder-message')),
        ),
      ),
    );
    expect(manager.status('test')['recordingState'], 'failed');
    expect(File('${dir.path}/result.mp4').lengthSync(), 0);
  });

  test(
    'existing destination prevents capture and survives unchanged',
    () async {
      final path = '${dir.path}/result.mp4';
      await File(path).writeAsString('existing');
      var captures = 0;
      final manager = RecordingManager();
      addTearDown(manager.dispose);
      await expectLater(
        manager.start(
          owner: 'test',
          target: target,
          path: path,
          deadline: deadline(),
          recorder: PngScreenRecorder(
            capture: () async {
              captures++;
              return png;
            },
            close: () async {},
            encoder: encoder,
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(captures, 0);
      expect(File(path).readAsStringSync(), 'existing');
    },
  );
}
