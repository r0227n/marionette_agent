import 'dart:async';
import 'dart:io';

import 'platform_recorder.dart';
import 'recorder.dart';
import '../platform_exception.dart';

/// Host-independent lifecycle and artifact ownership for platform recordings.
/// The caller serializes requests per owner. Device reservations are synchronous
/// across owners, including while a recorder is starting or finalizing.
class RecordingManager {
  RecordingManager({ScreenRecorder? recorder})
    : _recorder = recorder ?? const PlatformScreenRecorder();
  final ScreenRecorder _recorder;
  final _entries = <String, _Entry>{};
  final _devices = <String>{};
  bool _disposed = false;
  Future<void>? _disposing;

  bool contains(String owner) => _entries.containsKey(owner);

  Map<String, Object?> status(String owner) =>
      _entries[owner]?.info ?? {'recordingState': 'idle'};

  Future<Map<String, Object?>> start({
    required String owner,
    required RecordingTarget target,
    required String path,
    required DateTime deadline,
  }) async {
    _check(deadline);
    if (_disposed) {
      throw const PlatformException('IO_ERROR', 'Recorder is shutting down');
    }
    validateTarget(target, path);
    final previous = _entries[owner];
    if (previous != null && !previous.complete) {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Session already has an active recording',
      );
    }
    if (!_devices.add(target.key)) {
      throw const PlatformException(
        'SESSION_CONFLICT',
        'Device already has an active recording',
      );
    }
    final entry = _Entry(target, path);
    _entries[owner] = entry;
    var reserved = false;
    try {
      // Reserve the destination exclusively; tools write into a private sibling
      // directory and cannot overwrite an existing user file, directory or link.
      await File(path).create(exclusive: true);
      reserved = true;
      entry.staging = await Directory(File(path).parent.path)
          .createTemp('.marionette-record-');
      final extension = target.platform == RecordingPlatform.macos
          ? 'mov'
          : 'mp4';
      entry.stagingPath = '${entry.staging!.path}/capture.$extension';
      _check(deadline);
      final startupLimit = DateTime.now().add(const Duration(seconds: 30));
      entry.handle = await _recorder.start(
        target,
        entry.stagingPath!,
        deadline.isBefore(startupLimit) ? deadline : startupLimit,
      );
      if (_disposed) {
        throw const PlatformException('IO_ERROR', 'Recorder is shutting down');
      }
      _check(deadline);
      entry.started = DateTime.now();
      entry.state = 'recording';
      // Automatic Android limit or unexpected recorder exit is finalized too.
      unawaited(
        entry.handle!.ended
            .then((_) => _finish(entry))
            .catchError((Object _) {}),
      );
      return entry.info;
    } catch (error) {
      await entry.handle?.stop().catchError((Object _) {});
      if (reserved) {
        await File(path).delete().catchError((Object _) => File(path));
      }
      await entry.staging
          ?.delete(recursive: true)
          .catchError((Object _) => entry.staging!);
      _devices.remove(target.key);
      if (identical(_entries[owner], entry)) {
        if (previous == null) {
          _entries.remove(owner);
        } else {
          _entries[owner] = previous;
        }
      }
      if (error is PlatformException) rethrow;
      throw const PlatformException(
        'IO_ERROR',
        'Cannot start screen recording',
        hint: 'Use a new output path in an existing writable directory.',
      );
    } finally {
      entry.startDone.complete();
    }
  }

  Future<Map<String, Object?>> stop(String owner, DateTime deadline) async {
    _check(deadline);
    final entry = _entries[owner];
    if (entry == null) return status(owner);
    // A timeout only bounds the response: finalization keeps its device lock
    // and status remains stopping until the bounded backend cleanup completes.
    try {
      await _finish(entry).timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Recording is still finalizing',
        hint:
            'Check record status; do not restart the operation automatically.',
      );
    }
    if (entry.error case final PlatformException error) throw error;
    return entry.info;
  }

  Future<void> _finish(_Entry entry) => entry.finishing ??= _finalize(entry);

  Future<void> _finalize(_Entry entry) async {
    entry.state = 'stopping';
    try {
      await entry.handle!.stop();
      final staged = File(entry.stagingPath!);
      if (!await staged.exists() || await staged.length() == 0) {
        throw const PlatformException('IO_ERROR', 'Recorder produced no video');
      }
      entry.bytes = await staged.length();
      // Copy into our reserved destination. Do not rename over an arbitrary file.
      // As with screenshot saving, hostile replacement after reservation is out
      // of scope; ordinary pre-existing paths are rejected before capture.
      await staged.openRead().pipe(File(entry.path).openWrite());
      entry.state = 'stopped';
      await entry.staging!.delete(recursive: true);
    } catch (error) {
      entry.error = error is PlatformException
          ? error
          : const PlatformException('IO_ERROR', 'Cannot finalize recording');
      entry.state = 'failed';
      // Retain staging for recovery; never claim an incomplete file is complete.
    } finally {
      entry.finished = DateTime.now();
      _devices.remove(entry.target.key);
    }
  }

  Future<Map<String, Object?>?> close(String owner, DateTime deadline) async {
    final entry = _entries[owner];
    if (entry == null) return null;
    _check(deadline);
    try {
      await _finish(entry).timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      throw const PlatformException('TIMEOUT', 'Recording is still finalizing');
    }
    _entries.remove(owner);
    return entry.info;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await Future.wait(
      _entries.values.toList().map((entry) => entry.startDone.future),
    );
    await Future.wait(
      _entries.values.where((entry) => entry.handle != null).map(_finish),
    );
    _entries.clear();
    _devices.clear();
  }
}

void _check(DateTime deadline) {
  if (!deadline.isAfter(DateTime.now())) {
    throw const PlatformException(
      'TIMEOUT',
      'Recording request deadline exceeded',
    );
  }
}

/// Validate before invoking tools, including direct callers and IPC adapters.
void validateTarget(RecordingTarget target, String path) {
  final valid = switch (target.platform) {
    RecordingPlatform.web ||
    RecordingPlatform.linux ||
    RecordingPlatform.windows => throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'Screen recording is not implemented for this platform',
    ),
    RecordingPlatform.ios => RegExp(
      r'^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$',
    ).hasMatch(target.device),
    RecordingPlatform.android => RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
    ).hasMatch(target.device),
    RecordingPlatform.macos => RegExp(
      r'^[1-9][0-9]{0,2}$',
    ).hasMatch(target.device),
  };
  final extension = target.platform == RecordingPlatform.macos
      ? '.mov'
      : '.mp4';
  if (!valid ||
      !path.startsWith('/') ||
      path.contains('\u0000') ||
      !path.endsWith(extension)) {
    throw PlatformException(
      'INVALID_ARGUMENT',
      'Invalid recording target or output path',
      hint:
          'Specify a Simulator UDID, adb serial or positive display index and an absolute $extension path.',
    );
  }
}

class _Entry {
  _Entry(this.target, this.path);
  final RecordingTarget target;
  final String path;
  String state = 'starting';
  final startDone = Completer<void>();
  Directory? staging;
  String? stagingPath;
  RecordingHandle? handle;
  DateTime? started, finished;
  int? bytes;
  PlatformException? error;
  Future<void>? finishing;
  bool get complete => state == 'stopped' || state == 'failed';
  Map<String, Object?> get info => {
    'recordingState': state,
    'platform': target.platform.name,
    'device': target.device,
    'path': path,
    'startedAt': started?.toUtc().toIso8601String(),
    'elapsedMs': started == null
        ? 0
        : (finished ?? DateTime.now()).difference(started!).inMilliseconds,
    'bytes': bytes,
    if (error != null)
      'failure': {
        'code': error!.code,
        'message': error!.message,
        'hint': error!.hint,
      },
    if (state == 'failed') 'recoveryPath': stagingPath,
  };
}
