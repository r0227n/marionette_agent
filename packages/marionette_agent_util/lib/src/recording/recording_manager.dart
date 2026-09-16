import 'dart:async';
import 'dart:io';

import 'platform_recorder.dart';
import 'recorder.dart';
import 'web_target.dart';
import '../platform_exception.dart';

/// Host-independent lifecycle and artifact ownership for platform recordings.
/// The caller serializes requests per owner. Device reservations are synchronous
/// across owners, including while a recorder is starting or finalizing.
class RecordingManager {
  RecordingManager({
    ScreenRecorder? recorder,
    this.shutdownTimeout = const Duration(seconds: 60),
  }) : _recorder = recorder ?? const PlatformScreenRecorder();
  final ScreenRecorder _recorder;
  final Duration shutdownTimeout;
  final _entries = <String, _Entry>{};
  final _devices = <String>{};
  final _active = <_Entry>{};
  final _cleanups = <Future<void>>{};
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
    ScreenRecorder? recorder,
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
    _active.add(entry);
    var reserved = false;
    Future<RecordingHandle>? starting;
    try {
      // Reserve the destination exclusively; tools write into a private sibling
      // directory and cannot overwrite an existing user file, directory or link.
      await File(path).create(exclusive: true);
      reserved = true;
      _checkActive(entry);
      entry.staging = await Directory(File(path).parent.path)
          .createTemp('.marionette-record-');
      entry.stagingPath = '${entry.staging!.path}/capture${target.extension}';
      _checkActive(entry);
      _check(deadline);
      final startupLimit = DateTime.now().add(const Duration(seconds: 30));
      final startDeadline = deadline.isBefore(startupLimit)
          ? deadline
          : startupLimit;
      starting = (recorder ?? _recorder).start(
        target,
        entry.stagingPath!,
        startDeadline,
      );
      try {
        entry.handle = await starting.timeout(
          startDeadline.difference(DateTime.now()),
        );
      } on TimeoutException {
        throw const PlatformException(
          'TIMEOUT',
          'Recording startup is still being cleaned up',
          hint: 'Do not restart the operation automatically.',
        );
      }
      if (_disposed) {
        throw const PlatformException('IO_ERROR', 'Recorder is shutting down');
      }
      _check(deadline);
      entry.started = DateTime.now();
      entry.state = 'recording';
      // Automatic Android limit or unexpected recorder exit is finalized too.
      unawaited(
        entry.handle!.ended
            .catchError((Object _) {})
            .then((_) => _finish(entry))
            .catchError((Object _) {}),
      );
      return entry.info;
    } catch (error) {
      if (identical(_entries[owner], entry)) {
        if (previous == null) {
          _entries.remove(owner);
        } else {
          _entries[owner] = previous;
        }
      }
      final failure = error is PlatformException
          ? error
          : const PlatformException(
              'IO_ERROR',
              'Cannot start screen recording',
              hint: 'Use a new output path in an existing writable directory.',
            );
      final cleanup = _cleanupFailedStart(entry, starting, reserved: reserved);
      if (failure.code == 'TIMEOUT') {
        _trackCleanup(cleanup);
      } else {
        await cleanup;
      }
      throw failure;
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
      _checkActive(entry);
      final staged = File(entry.stagingPath!);
      if (!await staged.exists() || await staged.length() == 0) {
        throw const PlatformException('IO_ERROR', 'Recorder produced no video');
      }
      entry.bytes = await staged.length();
      // Copy into our reserved destination. Do not rename over an arbitrary file.
      // As with screenshot saving, hostile replacement after reservation is out
      // of scope; ordinary pre-existing paths are rejected before capture.
      _checkActive(entry);
      final sink = entry.sink = File(entry.path).openWrite();
      unawaited(sink.done.catchError((Object _) {}));
      final reader = entry.copy = StreamIterator(staged.openRead());
      while (await reader.moveNext()) {
        _checkActive(entry);
        sink.add(reader.current);
        await sink.flush();
      }
      await sink.close();
      _checkActive(entry);
      entry.state = 'stopped';
      await entry.staging!.delete(recursive: true);
    } catch (error) {
      entry.error = error is PlatformException
          ? error
          : const PlatformException('IO_ERROR', 'Cannot finalize recording');
      entry.state = 'failed';
      final copy = entry.copy;
      if (copy != null) unawaited(_settled(copy.cancel()));
      final sink = entry.sink;
      if (sink != null) unawaited(_settled(sink.close()));
      // Retain staging for recovery; never claim an incomplete file is complete.
    } finally {
      entry.finished = DateTime.now();
      _releaseDeviceWhenTerminated(entry);
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
    try {
      await _drain().timeout(shutdownTimeout);
    } on TimeoutException {
      // Keep private staging for recovery. Never remove a file that an
      // outstanding OS operation may still be using, or publish it as complete.
      final entries = {..._active, ..._entries.values};
      await Future.wait(entries.map(_abort))
          .timeout(const Duration(seconds: 5), onTimeout: () => <void>[]);
    } finally {
      _entries.clear();
      _devices.clear();
    }
  }

  Future<void> _drain() async {
    await Future.wait(
      _entries.values.toList().map((entry) => entry.startDone.future),
    );
    await Future.wait(
      _entries.values
          .toList()
          .where((entry) => entry.handle != null)
          .map(_finish),
    );
    while (_cleanups.isNotEmpty) {
      await Future.wait(_cleanups.toList());
    }
  }

  Future<void> _abort(_Entry entry) async {
    if (entry.state == 'stopped') return;
    entry.aborted = true;
    entry.state = 'failed';
    entry.error = const PlatformException(
      'TIMEOUT',
      'Recording shutdown expired',
    );
    entry.finished = DateTime.now();
    await Future.wait([
      if (entry.handle case final handle?) _settled(handle.abort()),
      if (entry.copy case final copy?) _settled(copy.cancel()),
      if (entry.sink case final sink?) _settled(sink.close()),
    ]);
  }

  void _checkActive(_Entry entry) {
    if (entry.aborted) throw entry.error!;
  }

  Future<void> _cleanupFailedStart(
    _Entry entry,
    Future<RecordingHandle>? starting, {
    required bool reserved,
  }) async {
    try {
      var handle = entry.handle;
      if (handle == null && starting != null) {
        try {
          handle = await starting;
          entry.handle = handle;
        } catch (_) {
          // The backend rejected startup and has no handle to terminate.
        }
      }
      if (handle != null) {
        if (entry.aborted) {
          await _settled(handle.abort());
          return;
        }
        try {
          await handle.stop();
        } catch (_) {
          // Preserve the original startup error; termination is observed below.
        }
        if (handle.isRunning) await _settled(handle.ended);
      }
    } finally {
      if (reserved && !entry.aborted) {
        await File(entry.path)
            .delete()
            .catchError((Object _) => File(entry.path));
      }
      if (!entry.aborted) {
        await entry.staging
            ?.delete(recursive: true)
            .catchError((Object _) => entry.staging!);
      }
      _devices.remove(entry.target.key);
      _active.remove(entry);
    }
  }

  void _releaseDeviceWhenTerminated(_Entry entry) {
    final handle = entry.handle;
    if (handle == null || !handle.isRunning) {
      _devices.remove(entry.target.key);
      _active.remove(entry);
      return;
    }
    final cleanup = _settled(handle.ended).whenComplete(() {
      _devices.remove(entry.target.key);
      _active.remove(entry);
    });
    _trackCleanup(cleanup);
  }

  void _trackCleanup(Future<void> cleanup) {
    _cleanups.add(cleanup);
    unawaited(cleanup.whenComplete(() => _cleanups.remove(cleanup)));
  }
}

Future<void> _settled(Future<void> future) async {
  try {
    await future;
  } catch (_) {
    // Completion still proves the capture process has terminated.
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
  if (target.fps != null && (target.fps! < 1 || target.fps! > 60)) {
    throw const PlatformException(
      'INVALID_ARGUMENT',
      'FPS must be from 1 to 60',
    );
  }
  final valid = switch (target.platform) {
    RecordingPlatform.flutter => RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$',
    ).hasMatch(target.device),
    RecordingPlatform.linux ||
    RecordingPlatform.windows => throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'Screen recording is not implemented for this platform',
    ),
    RecordingPlatform.web => WebRecordingTarget.parse(target.device) != null,
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
  final extension = target.extension;
  if (!valid ||
      !path.startsWith('/') ||
      path.contains('\u0000') ||
      !path.endsWith(extension)) {
    throw PlatformException(
      'INVALID_ARGUMENT',
      'Invalid recording target or output path',
      hint:
          'Specify a Simulator UDID, adb serial or positive display index, or Web display/page pair and an absolute $extension path.',
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
  bool aborted = false;
  StreamIterator<List<int>>? copy;
  IOSink? sink;
  bool get complete => state == 'stopped' || state == 'failed';
  Map<String, Object?> get info => {
    'recordingState': state,
    'platform': target.platform.name,
    if (target.fps != null) 'fps': target.fps,
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
