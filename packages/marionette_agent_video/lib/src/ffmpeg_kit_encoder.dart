import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
// Version-pinned FFI seam: the public Flutter barrel exports dart:ui. Import
// only the generated C ABI so both Dart CLI and Flutter callers can use it.
// ignore: implementation_imports
import 'package:ffmpeg_kit_extended_flutter/src/generated/ffmpeg_kit_bindings_native.dart'
    as native;
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Uses the package's bundled LGPL FFmpeg runtime, never a PATH executable.
/// Native work runs asynchronously; polling keeps request deadlines responsive.
class FfmpegKitVideoEncoder implements VideoEncoder {
  static bool _initialized = false;
  _Encoding? _active;

  @override
  List<String> get h264Arguments => const [
    '-c:v',
    'h264_videotoolbox',
    '-allow_sw',
    '1',
  ];
  @override
  bool get isRunning => _active != null;
  @override
  Future<void> get ended => _active?.done.future.then((_) {}) ?? Future.value();

  void _initialize() {
    if (!Platform.isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Bundled host encoding currently requires macOS',
      );
    }
    if (_initialized) return;
    try {
      native.ffmpeg_kit_config_set_log_level(
        native.FFmpegKitLogLevel.FFMPEG_KIT_LOG_LEVEL_QUIET,
      );
      native.ffmpeg_kit_initialize();
      final capabilities = [
        (native.ffmpeg_kit_packages_get_registered_decoders(), 'png'),
        (
          native.ffmpeg_kit_packages_get_registered_encoders(),
          'h264_videotoolbox',
        ),
        (native.ffmpeg_kit_packages_get_registered_demuxers(), 'concat'),
        (native.ffmpeg_kit_packages_get_registered_muxers(), 'mp4'),
        (native.ffmpeg_kit_packages_get_registered_filters(), 'pad'),
        (
          native.ffmpeg_kit_packages_get_registered_bitstream_filters(),
          'setts',
        ),
      ];
      var supported = true;
      for (final (pointer, required) in capabilities) {
        if (pointer == nullptr) {
          supported = false;
          continue;
        }
        try {
          supported &= pointer
              .cast<Utf8>()
              .toDartString()
              .split(',')
              .map((s) => s.trim())
              .contains(required);
        } finally {
          native.ffmpeg_kit_free(pointer.cast());
        }
      }
      if (!supported) {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'Bundled FFmpeg lacks required recording codecs',
          hint: 'Build with the workspace video/LGPL FFmpegKit configuration.',
        );
      }
      _initialized = true;
    } on PlatformException {
      rethrow;
    } catch (_) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Bundled FFmpeg runtime is unavailable',
        hint: 'Rebuild or reinstall the complete CLI bundle, including its native libraries.',
      );
    }
  }

  @override
  Future<void> run(List<String> arguments, DateTime deadline) async {
    _remaining(deadline);
    if (_active != null) {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Encoder already has an active session',
      );
    }
    _initialize();
    final argv = calloc<Pointer<Char>>(arguments.length);
    final strings = <Pointer<Utf8>>[];
    late Pointer<Void> handle;
    try {
      for (var i = 0; i < arguments.length; i++) {
        if (arguments[i].contains('\u0000')) {
          throw const PlatformException(
            'INVALID_ARGUMENT',
            'Invalid encoding argument',
          );
        }
        final value = arguments[i].toNativeUtf8(allocator: calloc);
        strings.add(value);
        argv[i] = value.cast();
      }
      handle = native.ffmpeg_kit_create_session_from_argv(
        arguments.length,
        argv,
      );
    } finally {
      for (final string in strings) {
        calloc.free(string);
      }
      calloc.free(argv);
    }
    if (handle == nullptr) {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot create video encoding session',
      );
    }
    final encoding = _active = _Encoding(handle);
    unawaited(encoding.done.future.catchError((Object _) => -1));
    try {
      native.ffmpeg_kit_session_execute_async(handle);
    } catch (_) {
      native.ffmpeg_kit_close_session(handle);
      _active = null;
      throw const PlatformException('IO_ERROR', 'Cannot start video encoding');
    }
    unawaited(_watch(encoding));
    try {
      final code = await encoding.done.future.timeout(
        deadline.difference(DateTime.now()),
      );
      if (encoding.cancelled || code != 0) {
        throw const PlatformException('IO_ERROR', 'Video encoding failed');
      }
    } on TimeoutException {
      await abort();
      throw const PlatformException(
        'TIMEOUT',
        'Video encoding deadline exceeded',
      );
    }
  }

  Future<void> _watch(_Encoding encoding) async {
    try {
      while (native.ffmpeg_kit_session_get_state(encoding.handle).value < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      encoding.terminal = true;
      final sessionId = native.ffmpeg_kit_session_get_session_id(
        encoding.handle,
      );
      while (native.ffmpeg_kit_config_messages_in_transmit(sessionId) > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      var code = native.ffmpeg_kit_session_get_return_code(encoding.handle);
      // FFmpegKit can return zero after a decode error and leave a partial
      // movie. Native structured error levels are part of completion too;
      // never expose their messages (which may contain private file paths).
      for (
        var i = 0;
        i < native.ffmpeg_kit_session_get_logs_count(encoding.handle);
        i++
      ) {
        final level = native.ffmpeg_kit_session_get_log_level_at(
          encoding.handle,
          i,
        );
        if (level >= 0 && level <= 16) code = 1;
      }
      native.ffmpeg_kit_close_session(encoding.handle);
      if (identical(_active, encoding)) _active = null;
      encoding.done.complete(code);
    } catch (_) {
      // Unconfirmed native termination retains ownership. Do not free a handle
      // still in use or let its staging directory/device be reused.
      if (encoding.terminal && identical(_active, encoding)) _active = null;
      encoding.done.completeError(
        const PlatformException(
          'IO_ERROR',
          'Cannot confirm video encoding completion',
        ),
      );
    }
  }

  @override
  Future<void> abort() async {
    final encoding = _active;
    if (encoding == null) return;
    if (!encoding.cancelled) {
      encoding.cancelled = true;
      native.ffmpeg_kit_session_cancel(encoding.handle);
    }
    try {
      await encoding.done.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The watcher continues to own the handle until native termination.
    }
  }
}

class _Encoding {
  _Encoding(this.handle);
  final Pointer<Void> handle;
  final done = Completer<int>();
  bool terminal = false, cancelled = false;
}

Duration _remaining(DateTime deadline) {
  final duration = deadline.difference(DateTime.now());
  if (duration <= Duration.zero) {
    throw const PlatformException(
      'TIMEOUT',
      'Video encoding deadline exceeded',
    );
  }
  return duration;
}
