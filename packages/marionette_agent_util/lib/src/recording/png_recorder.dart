import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../platform_exception.dart';
import 'recorder.dart';

/// Samples application PNGs without a display capture permission or a window.
/// PNGs are persisted with monotonic acquisition times; encoding preserves those
/// times instead of claiming that slow captures achieved the requested rate.
class PngScreenRecorder implements ScreenRecorder {
  PngScreenRecorder({
    required this.capture,
    required this.close,
    this.encoder = 'ffmpeg',
  });
  final Future<List<int>> Function() capture;
  final Future<void> Function() close;
  final String encoder;

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    final handle = _PngRecording(
      capture,
      close,
      encoder,
      stagingPath,
      target.fps ?? 10,
    );
    try {
      await handle.initialize(deadline);
      return handle;
    } catch (_) {
      await handle.abort();
      rethrow;
    }
  }
}

class _PngRecording implements RecordingHandle {
  _PngRecording(
    this.capture,
    this.closeFeed,
    this.encoder,
    this.path,
    this.fps,
  );
  final Future<List<int>> Function() capture;
  final Future<void> Function() closeFeed;
  final String encoder, path;
  final int fps;
  final _clock = Stopwatch();
  final _ended = Completer<void>();
  final _times = <int>[];
  final _frames = <String>[];
  late Directory directory;
  (int, int)? _dimensions;
  Future<void>? _loop, _stopped, _closed;
  Process? _process;
  bool _stopping = false, _aborted = false, _loopDone = true;
  PlatformException? _failure;
  int? _stopMicros;

  @override
  Future<void> get ended => _ended.future;
  @override
  bool get isRunning => !_loopDone || _process != null;

  Future<void> initialize(DateTime deadline) async {
    // Fail before sampling if the required encoder is unavailable.
    await _runEncoder(['-version'], deadline);
    directory = await Directory('${File(path).parent.path}/frames').create();
    final first = await capture().timeout(_remaining(deadline));
    await _save(first, 0);
    _clock.start();
    _loopDone = false;
    _loop = _sample();
  }

  Future<void> _save(List<int> bytes, int micros) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24 ||
        bytes.length > 64 * 1024 * 1024 ||
        List.generate(8, (i) => i).any((i) => bytes[i] != signature[i]) ||
        String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
      throw const PlatformException('IO_ERROR', 'Capture did not return a PNG');
    }
    final data = ByteData.sublistView(
      Uint8List.fromList(bytes.sublist(16, 24)),
    );
    final dimensions = (data.getUint32(0), data.getUint32(4));
    if (dimensions.$1 == 0 ||
        dimensions.$2 == 0 ||
        dimensions.$1 > 8192 ||
        dimensions.$2 > 8192 ||
        dimensions.$1 * dimensions.$2 > 16 * 1024 * 1024) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Recording image is too large',
      );
    }
    if (_dimensions != null && dimensions != _dimensions) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Recording image size changed',
      );
    }
    _dimensions = dimensions;
    final name = 'frame-${_frames.length}.png';
    await File('${directory.path}/$name').writeAsBytes(bytes, flush: true);
    _frames.add(name);
    _times.add(micros);
  }

  Future<void> _sample() async {
    try {
      while (!_stopping) {
        await Future<void>.delayed(Duration(microseconds: 1000000 ~/ fps));
        if (_stopping) break;
        final bytes = await capture().timeout(const Duration(seconds: 5));
        if (_stopping) break;
        await _save(bytes, _clock.elapsedMicroseconds);
      }
    } catch (error) {
      if (!_stopping) {
        _failure = error is PlatformException
            ? error
            : const PlatformException(
                'CONNECTION_LOST',
                'Application capture failed',
              );
        if (!_ended.isCompleted) _ended.complete();
      }
    } finally {
      _loopDone = true;
    }
  }

  Future<void> _close() =>
      _closed ??= closeFeed().timeout(const Duration(seconds: 5));

  @override
  Future<void> stop() => _stopped ??= _stop();

  Future<void> _stop() async {
    _stopMicros ??= _clock.elapsedMicroseconds;
    _stopping = true;
    try {
      await _close();
      await _loop;
      if (_aborted) {
        throw const PlatformException('IO_ERROR', 'Recording was aborted');
      }
      if (_failure != null) throw _failure!;
      if (_frames.isEmpty) {
        throw const PlatformException('IO_ERROR', 'No recording frames');
      }
      // The concat demuxer timestamps PNGs to milliseconds. Keep the final
      // packet positive even when stop lands within the same millisecond.
      final end = _stopMicros!.clamp(_times.last + 1000, 1 << 62);
      final manifest = StringBuffer('ffconcat version 1.0\n');
      for (var i = 0; i < _frames.length; i++) {
        final next = i + 1 < _times.length ? _times[i + 1] : end;
        final duration = (next - _times[i]).clamp(1000, 1 << 62) / 1000000;
        manifest
          ..writeln("file '${_frames[i]}'")
          ..writeln('option framerate 1000')
          ..writeln('duration ${duration.toStringAsFixed(6)}');
      }
      await File('${directory.path}/frames.ffconcat')
          .writeAsString(manifest.toString());
      await _runEncoder([
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-xerror',
        '-n',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        '${directory.path}/frames.ffconcat',
        '-an',
        '-vf',
        'pad=ceil(iw/2)*2:ceil(ih/2)*2',
        '-fps_mode',
        'vfr',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-pix_fmt',
        'yuv420p',
        '-enc_time_base',
        '1:1000000',
        '-bf',
        '0',
        '-video_track_timescale',
        '1000000',
        '-bsf:v',
        "setts=duration='if(eq(N,${_frames.length - 1}),"
            "${end / 1000000}/TB-PTS,NEXT_PTS-PTS)'",
        '-movflags',
        '+faststart',
        path,
      ], DateTime.now().add(const Duration(seconds: 30)));
    } finally {
      _clock.stop();
      if (!_ended.isCompleted) _ended.complete();
    }
  }

  Future<void> _runEncoder(List<String> args, DateTime deadline) async {
    Process? child;
    var expired = false;
    final starting = Process.start(encoder, args);
    unawaited(
      starting.then((process) {
        if (expired || _aborted) process.kill(ProcessSignal.sigkill);
      }, onError: (Object _) {}),
    );
    try {
      child = await starting.timeout(_remaining(deadline));
      if (_aborted) {
        throw const PlatformException('IO_ERROR', 'Recording was aborted');
      }
      _process = child;
      final streams = Future.wait([
        child.stdout.drain<void>(),
        child.stderr.drain<void>(),
      ]);
      final code = await child.exitCode.timeout(_remaining(deadline));
      await streams.timeout(_remaining(deadline));
      if (code != 0) {
        throw const PlatformException(
          'IO_ERROR',
          'Video encoding failed',
          hint: 'Check the installed ffmpeg supports PNG and libx264.',
        );
      }
    } on ProcessException {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'ffmpeg is required for Flutter recording',
      );
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Video encoding deadline exceeded',
      );
    } finally {
      expired = true;
      if (child != null) {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 5));
        if (identical(_process, child)) _process = null;
      }
    }
  }

  @override
  Future<void> abort() async {
    _aborted = true;
    _stopping = true;
    _process?.kill(ProcessSignal.sigkill);
    try {
      await _close();
    } catch (_) {}
    try {
      await _loop?.timeout(const Duration(seconds: 6));
    } catch (_) {}
    final process = _process;
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
        if (identical(_process, process)) _process = null;
      } catch (_) {}
    }
    if (!_ended.isCompleted) _ended.complete();
  }
}

Duration _remaining(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) throw TimeoutException('Capture deadline');
  return remaining;
}
