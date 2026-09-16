import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var available = true;
  for (final command in ['ffmpeg', 'ffprobe']) {
    try {
      available &= (await Process.run(command, ['-version'])).exitCode == 0;
    } on ProcessException {
      available = false;
    }
  }
  test(
    'real MP4 keeps every sample and its final presentation duration',
    () async {
      final dir = await Directory.systemTemp.createTemp('png-encoding-test-');
      addTearDown(() => dir.delete(recursive: true));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII=',
      );
      final third = Completer<void>();
      var captured = 0;
      final output = '${dir.path}/result.mp4';
      final handle =
          await PngScreenRecorder(
            capture: () async {
              if (++captured == 3) third.complete();
              return png;
            },
            close: () async {},
          ).start(
            const RecordingTarget(RecordingPlatform.flutter, 'test', fps: 10),
            output,
            DateTime.now().add(const Duration(seconds: 5)),
          );
      addTearDown(handle.abort);
      await third.future;
      await handle.stop();
      final manifest = await File('${dir.path}/frames/frames.ffconcat')
          .readAsString();
      final durations = RegExp(r'duration ([0-9.]+)')
          .allMatches(manifest)
          .map((m) => double.parse(m[1]!))
          .toList();
      final probe = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_frames',
        '-show_entries',
        'frame=best_effort_timestamp_time,duration_time:format=duration',
        '-of',
        'json',
        output,
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      final data = jsonDecode(probe.stdout as String) as Map<String, dynamic>;
      final frames = data['frames'] as List;
      expect(frames, hasLength(durations.length));
      expect(frames.length, greaterThanOrEqualTo(2));
      var time = 0.0;
      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i] as Map;
        final pts = double.parse(frame['best_effort_timestamp_time'] as String);
        expect(pts, closeTo(time, .001));
        expect(double.parse(frame['duration_time'] as String), greaterThan(0));
        time += durations[i];
      }
      final last = frames.last as Map;
      final end =
          double.parse(last['best_effort_timestamp_time'] as String) +
          double.parse(last['duration_time'] as String);
      expect(end, closeTo(time, .000002));
      expect(
        double.parse((data['format'] as Map)['duration'] as String),
        closeTo(time, .000002),
      );
      final decoded = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-nostdin',
        '-xerror',
        '-i',
        output,
        '-fps_mode',
        'passthrough',
        '-enc_time_base',
        'demux',
        '-f',
        'null',
        '-',
      ]);
      expect(decoded.exitCode, 0, reason: decoded.stderr.toString());
    },
    skip: available ? false : 'Requires local ffmpeg and ffprobe',
  );
  test(
    'corrupt PNG between valid frames fails without publishing a partial MP4',
    () async {
      final dir = await Directory.systemTemp.createTemp('png-corrupt-test-');
      addTearDown(() => dir.delete(recursive: true));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII=',
      );
      var captures = 0;
      final sampled = Completer<void>();
      final pending = Completer<List<int>>();
      final manager = RecordingManager();
      addTearDown(manager.dispose);
      final output = '${dir.path}/result.mp4';
      await manager.start(
        owner: 'test',
        target: const RecordingTarget(
          RecordingPlatform.flutter,
          'test',
          fps: 60,
        ),
        path: output,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        recorder: PngScreenRecorder(
          capture: () async {
            if (++captures == 4) {
              sampled.complete();
              return pending.future;
            }
            return captures == 2 ? png.sublist(0, 24) : png;
          },
          close: () async {
            if (!pending.isCompleted) pending.complete(png);
          },
        ),
      );
      await sampled.future;
      await expectLater(
        manager.stop('test', DateTime.now().add(const Duration(seconds: 10))),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
        ),
      );
      expect(manager.status('test')['recordingState'], 'failed');
      expect(File(output).lengthSync(), 0);
    },
    skip: available ? false : 'Requires local ffmpeg and ffprobe',
  );
}
