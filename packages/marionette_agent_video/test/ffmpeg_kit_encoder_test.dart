import 'dart:io';

import 'package:marionette_agent_video/marionette_agent_video.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 10));
  const realtime = [
    '-nostdin',
    '-loglevel',
    'quiet',
    '-re',
    '-f',
    'lavfi',
    '-i',
    'color=c=red:s=64x64:r=10:d=60',
    '-f',
    'null',
    '-',
  ];

  test(
    'bundled encoding uses literal argv and cancellation is session scoped',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ffmpeg-kit-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cancelled = FfmpegKitVideoEncoder();
      final completed = FfmpegKitVideoEncoder();
      addTearDown(cancelled.abort);
      addTearDown(completed.abort);
      final pending = cancelled.run(realtime, deadline());
      final failed = expectLater(
        pending,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
        ),
      );
      final path = '${directory.path}/literal quote\' and space.mp4';
      final encoding = completed.run([
        '-nostdin',
        '-loglevel',
        'quiet',
        '-n',
        '-f',
        'lavfi',
        '-i',
        'color=c=blue:s=64x64:r=10:d=0.2',
        '-an',
        ...completed.h264Arguments,
        '-pix_fmt',
        'yuv420p',
        path,
      ], deadline());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await cancelled.abort();
      await failed;
      await encoding;
      expect(await File(path).length(), greaterThan(0));
      expect(cancelled.isRunning, isFalse);
      expect(completed.isRunning, isFalse);
    },
  );

  test(
    'deadline cancels owned native work and permits a subsequent command',
    () async {
      final encoder = FfmpegKitVideoEncoder();
      addTearDown(encoder.abort);
      await expectLater(
        encoder.run(
          realtime,
          DateTime.now().add(const Duration(milliseconds: 100)),
        ),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
      expect(encoder.isRunning, isFalse);
      await encoder.run(['-version'], deadline());
      expect(encoder.isRunning, isFalse);
    },
  );
}
