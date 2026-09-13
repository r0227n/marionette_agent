import 'dart:async';
import 'dart:io';

import '../platform_exception.dart';
import 'recorder.dart';

/// Explicit FPS applies to the final video. Capture cadence is OS controlled.
/// ffmpeg receives only argv and private staging files, never a shell command.
Future<RecordingHandle> startAtFrameRate(
  ScreenRecorder recorder,
  RecordingTarget target,
  String path,
  DateTime deadline,
) async {
  await _convert(['-version'], deadline);
  final source = '$path.source${target.extension}';
  final handle = await recorder.start(
    RecordingTarget(target.platform, target.device),
    source,
    deadline,
  );
  return _FrameRateHandle(handle, source, path, target.fps!);
}

class _FrameRateHandle implements RecordingHandle {
  _FrameRateHandle(this.sourceHandle, this.source, this.destination, this.fps);
  final RecordingHandle sourceHandle;
  final String source, destination;
  final int fps;
  Future<void>? _stopping;
  Process? _encoding;
  bool _aborted = false;
  @override
  Future<void> get ended => sourceHandle.ended;
  @override
  bool get isRunning => sourceHandle.isRunning;
  @override
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    await sourceHandle.stop();
    if (_aborted) {
      throw const PlatformException('TIMEOUT', 'Recording conversion aborted');
    }
    await _convert(
      [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-n',
        '-i',
        source,
        '-an',
        '-vf',
        'fps=$fps',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        destination,
      ],
      DateTime.now().add(const Duration(seconds: 60)),
      onStart: (process) {
        _encoding = process;
        if (_aborted) process.kill(ProcessSignal.sigkill);
      },
    );
    if (_aborted) {
      throw const PlatformException('TIMEOUT', 'Recording conversion aborted');
    }
    await File(source).delete();
  }

  @override
  Future<void> abort() async {
    _aborted = true;
    _encoding?.kill(ProcessSignal.sigkill);
    await sourceHandle.abort();
  }
}

Future<void> _convert(
  List<String> args,
  DateTime deadline, {
  void Function(Process)? onStart,
}) async {
  Process? process;
  try {
    final pending = Process.start('ffmpeg', args);
    try {
      process = await pending.timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      unawaited(
        pending.then((value) {
          value.kill(ProcessSignal.sigkill);
        }),
      );
      rethrow;
    }
    onStart?.call(process);
    final streams = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
    ]);
    final code = await process.exitCode.timeout(
      deadline.difference(DateTime.now()),
    );
    await streams.timeout(deadline.difference(DateTime.now()));
    if (code != 0) {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot prepare or convert recording at the requested frame rate',
        hint: 'Install ffmpeg with the libx264 encoder.',
      );
    }
  } on PlatformException {
    rethrow;
  } on TimeoutException {
    throw const PlatformException(
      'TIMEOUT',
      'Recording conversion deadline exceeded',
    );
  } catch (_) {
    throw const PlatformException(
      'IO_ERROR',
      'ffmpeg is required when --fps is specified',
    );
  } finally {
    process?.kill(ProcessSignal.sigkill);
  }
}
