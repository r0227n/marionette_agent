import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_flutter/marionette_agent_flutter.dart';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

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
  final VideoEncoder _encoding = FfmpegKitVideoEncoder();
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
        ..._encoding.h264Arguments,
        '-pix_fmt',
        'yuv420p',
        destination,
      ],
      DateTime.now().add(const Duration(seconds: 60)),
      encoder: _encoding,
    );
    if (_aborted) {
      throw const PlatformException('TIMEOUT', 'Recording conversion aborted');
    }
    await File(source).delete();
  }

  @override
  Future<void> abort() async {
    _aborted = true;
    await _encoding.abort();
    await sourceHandle.abort();
  }
}

Future<void> _convert(
  List<String> args,
  DateTime deadline, {
  VideoEncoder? encoder,
}) => (encoder ?? FfmpegKitVideoEncoder()).run(args, deadline);
