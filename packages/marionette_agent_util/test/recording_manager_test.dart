import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

class Recorder implements ScreenRecorder {
  final handles = <Handle>[];
  Completer<void>? startGate;
  bool failStart = false;
  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) async {
    if (failStart) throw const PlatformException('IO_ERROR', 'not ready');
    final handle = Handle(path);
    handles.add(handle);
    await startGate?.future;
    return handle;
  }
}

class Handle implements RecordingHandle {
  Handle(this.path);
  final String path;
  final done = Completer<void>();
  Completer<void>? stopGate;
  bool fail = false;
  bool failBeforeEnding = false;
  int stops = 0;
  int aborts = 0;
  @override
  Future<void> abort() async {
    aborts++;
    if (!done.isCompleted) done.complete();
  }

  @override
  Future<void> get ended => done.future;
  @override
  bool get isRunning => !done.isCompleted;
  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    if (failBeforeEnding) {
      throw const PlatformException('IO_ERROR', 'termination not confirmed');
    }
    if (!done.isCompleted) done.complete();
    if (fail) throw const PlatformException('IO_ERROR', 'capture failed');
    await File(path).writeAsBytes([1, 2, 3]);
  }
}

class StalledFile implements File {
  final data = StreamController<List<int>>();
  bool cancelled = false;
  StalledFile() {
    data.onCancel = () {
      cancelled = true;
    };
  }
  @override
  Future<bool> exists() async => true;
  @override
  Future<int> length() async => 3;
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async => this;
  @override
  Stream<List<int>> openRead([int? start, int? end]) => data.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class StalledRead extends IOOverrides {
  final file = StalledFile();
  @override
  File createFile(String path) =>
      path.endsWith('/capture.mp4') ? file : super.createFile(path);
}

void main() {
  late Directory directory;
  late Recorder backend;
  late RecordingManager manager;
  const target = RecordingTarget(RecordingPlatform.android, 'emulator-5556');
  DateTime deadline([int ms = 2000]) =>
      DateTime.now().add(Duration(milliseconds: ms));
  Future<Map<String, Object?>> start(
    String owner, {
    String? path,
    RecordingTarget device = target,
    int deadlineMs = 2000,
  }) => manager.start(
    owner: owner,
    target: device,
    path: path ?? '${directory.path}/$owner.mp4',
    deadline: deadline(deadlineMs),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('record-test-');
    backend = Recorder();
    manager = RecordingManager(recorder: backend);
  });
  tearDown(() async {
    await manager.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'start returns ready, stop finalizes once and status remains available',
    () async {
      expect((await start('a'))['recordingState'], 'recording');
      expect(await File('${directory.path}/a.mp4').length(), 0);
      final results = await Future.wait([
        manager.stop('a', deadline()),
        manager.stop('a', deadline()),
      ]);
      expect(results.map((r) => r['recordingState']), everyElement('stopped'));
      expect(backend.handles.single.stops, 1);
      expect(await File('${directory.path}/a.mp4').readAsBytes(), [1, 2, 3]);
      expect(manager.status('a')['bytes'], 3);
      expect(await manager.close('a', deadline()), isNotNull);
      expect(manager.status('a')['recordingState'], 'idle');
    },
  );
  test(
    'device is reserved while starting and available after finalization',
    () async {
      backend.startGate = Completer();
      final first = start('a');
      while (backend.handles.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await expectLater(
        start('b'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SESSION_CONFLICT',
          ),
        ),
      );
      backend.startGate!.complete();
      await first;
      await manager.stop('a', deadline());
      await start('b');
    },
  );
  test('existing file, directory and symlink are never overwritten', () async {
    for (final type in ['file', 'directory', 'link']) {
      final path = '${directory.path}/$type.mp4';
      if (type == 'file') await File(path).writeAsString('precious');
      if (type == 'directory') await Directory(path).create();
      if (type == 'link') await Link(path).create('${directory.path}/missing');
      await expectLater(
        start('a', path: path),
        throwsA(isA<PlatformException>()),
      );
      expect(manager.contains('a'), false);
      expect(backend.handles, isEmpty);
    }
    expect(await File('${directory.path}/file.mp4').readAsString(), 'precious');
    expect(
      await Link('${directory.path}/link.mp4').target(),
      '${directory.path}/missing',
    );
    await start('a');
  });
  test('failed start removes reservation and releases device', () async {
    backend.failStart = true;
    await expectLater(start('a'), throwsA(isA<PlatformException>()));
    expect(await File('${directory.path}/a.mp4').exists(), false);
    backend.failStart = false;
    await start('b');
  });
  test('stop timeout keeps ownership until cleanup finishes', () async {
    await start('a');
    backend.handles.single.stopGate = Completer();
    await expectLater(
      manager.stop('a', deadline(10)),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
      ),
    );
    expect(manager.status('a')['recordingState'], 'stopping');
    await expectLater(start('b'), throwsA(isA<PlatformException>()));
    backend.handles.single.stopGate!.complete();
    await manager.stop('a', deadline());
    await start('b');
  });
  test(
    'failed stop keeps device reserved until termination is confirmed',
    () async {
      await start('a');
      final handle = backend.handles.single..failBeforeEnding = true;

      await expectLater(
        manager.stop('a', deadline()),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
        ),
      );
      expect(manager.status('a')['recordingState'], 'failed');
      await expectLater(
        start('b'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SESSION_CONFLICT',
          ),
        ),
      );

      handle.done.complete();
      await handle.ended;
      await Future<void>.delayed(Duration.zero);
      await start('b');
    },
  );
  test('start deadline returns while late handle cleanup continues', () async {
    backend.startGate = Completer<void>();
    final pending = start(
      'a',
      deadlineMs: 20,
    ).then<Object?>((value) => value, onError: (Object error) => error);
    while (backend.handles.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final handle = backend.handles.single;
    handle.stopGate = Completer<void>();

    await Future<void>.delayed(const Duration(milliseconds: 30));
    Object? result;
    try {
      result = await pending.timeout(const Duration(milliseconds: 200));
    } catch (error) {
      result = error;
    } finally {
      backend.startGate!.complete();
    }
    expect(
      result,
      isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
    );
    expect(manager.contains('a'), false);
    await expectLater(
      start('b'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'SESSION_CONFLICT',
        ),
      ),
    );

    handle.stopGate!.complete();
    await handle.ended;
    Map<String, Object?>? restarted;
    for (var attempt = 0; attempt < 50 && restarted == null; attempt++) {
      try {
        restarted = await start('b');
      } on PlatformException catch (error) {
        if (error.code != 'SESSION_CONFLICT') rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
    expect(restarted, containsPair('recordingState', 'recording'));
  });
  test(
    'automatic end finalizes; failed end is visible and close releases owner',
    () async {
      await start('a');
      backend.handles.single.fail = true;
      backend.handles.single.done.complete();
      await expectLater(
        manager.stop('a', deadline()),
        throwsA(isA<PlatformException>()),
      );
      expect(manager.status('a')['recordingState'], 'failed');
      expect(manager.status('a')['recoveryPath'], isNotNull);
      expect(
        (await manager.close('a', deadline()))!['recordingState'],
        'failed',
      );
      expect(manager.contains('a'), false);
      await start('b');
    },
  );
  test(
    'shutdown during start disposes the late handle and releases its output',
    () async {
      backend.startGate = Completer();
      final pending = start('a');
      final assertion = expectLater(pending, throwsA(isA<PlatformException>()));
      while (backend.handles.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final disposing = manager.dispose();
      backend.startGate!.complete();
      await assertion;
      await disposing;
      expect(backend.handles.single.stops, 1);
      expect(await File('${directory.path}/a.mp4').exists(), false);
      expect(manager.contains('a'), false);
    },
  );
  test('shutdown is bounded when startup never returns', () async {
    manager = RecordingManager(
      recorder: backend,
      shutdownTimeout: const Duration(milliseconds: 20),
    );
    backend.startGate = Completer<void>();
    final pending = start('a', deadlineMs: 5000);
    final assertion = expectLater(pending, throwsA(isA<PlatformException>()));
    while (backend.handles.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    var returned = false;
    try {
      await manager.dispose().timeout(const Duration(milliseconds: 200));
      returned = true;
    } on TimeoutException {
      // Release the fake after observing the unbounded shutdown regression.
    } finally {
      backend.startGate!.complete();
      await assertion;
    }
    expect(returned, isTrue);
    expect(backend.handles.single.aborts, 1);
  });
  test('shutdown aborts a stalled stop and retains recovery video', () async {
    manager = RecordingManager(
      recorder: backend,
      shutdownTimeout: const Duration(milliseconds: 20),
    );
    await start('a');
    final handle = backend.handles.single;
    handle.stopGate = Completer<void>();
    await File(handle.path).writeAsBytes([9, 8, 7]);
    await manager.dispose().timeout(const Duration(milliseconds: 200));
    expect(handle.aborts, 1);
    expect(await File(handle.path).readAsBytes(), [9, 8, 7]);
    expect(await File('${directory.path}/a.mp4').length(), 0);
    handle.stopGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The late stop must not publish or remove the recovery file.
    expect(await File(handle.path).exists(), isTrue);
    expect(await File('${directory.path}/a.mp4').length(), 0);
  });
  test(
    'shutdown cancels stalled file copy without publishing success',
    () async {
      final io = StalledRead();
      await IOOverrides.runWithIOOverrides(() async {
        manager = RecordingManager(
          recorder: backend,
          shutdownTimeout: const Duration(milliseconds: 20),
        );
        await start('a');
        await manager.dispose().timeout(const Duration(milliseconds: 200));
        expect(io.file.cancelled, isTrue);
        expect(await File('${directory.path}/a.mp4').length(), 0);
        expect(
          await Directory(backend.handles.single.path).parent.exists(),
          isTrue,
        );
      }, io);
      await io.file.data.close();
    },
  );
  test('failed ended notification finalizes and releases the device', () async {
    await start('a');
    final handle = backend.handles.single..fail = true;
    handle.done.completeError(StateError('stream failed'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.status('a')['recordingState'], 'failed');
    expect(handle.stops, 1);
    await start('b');
  });
  test('invalid device and suffix rejected before any recording', () async {
    await expectLater(
      start(
        'a',
        device: const RecordingTarget(RecordingPlatform.android, 'bad;command'),
      ),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      start('a', path: '${directory.path}/movie.mov'),
      throwsA(isA<PlatformException>()),
    );
    expect(backend.handles, isEmpty);
  });
}
