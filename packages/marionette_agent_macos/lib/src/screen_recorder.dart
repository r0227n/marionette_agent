import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

/// ScreenCaptureKit owns capture and encoding; no screencapture subprocess.
class MacosScreenRecorder implements ScreenRecorder {
  const MacosScreenRecorder();
  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String path,
    DateTime deadline,
  ) async {
    if (!Platform.isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'ScreenCaptureKit requires macOS',
      );
    }
    if (!screenCaptureAllowed()) {
      throw const PlatformException(
        'SCREEN_CAPTURE_PERMISSION_REQUIRED',
        'Enable Screen Recording permission for the invoking app',
      );
    }
    final work = await Directory.systemTemp.createTemp('mra-screenkit-');
    ProcessRecording? handle;
    try {
      await File('${work.path}/Recorder.swift').writeAsString(_source);
      await runRecordingCommand('/usr/bin/xcrun', [
        'swiftc',
        '-parse-as-library',
        '${work.path}/Recorder.swift',
        '-o',
        '${work.path}/recorder',
      ], deadline);
      final process = await spawnRecordingProcess('${work.path}/recorder', [
        target.device,
        path,
        '${target.fps ?? 30}',
      ]);
      handle = ProcessRecording(
        process,
        failureHint: 'ScreenCaptureKit requires macOS 15+, permission and an active display.',
      );
      handle.signalLocal = false;
      handle.beforeStop = () async {
        process.stdin.writeln('stop');
        await process.stdin.flush();
      };
      handle.afterStop = () async {
        await work.delete(recursive: true);
      };
      handle.beforeAbort = () async {
        await work.delete(recursive: true).catchError((Object _) => work);
      };
      await handle.waitForLine('MRA_RECORD_READY', deadline);
      return handle;
    } catch (_) {
      await handle?.abort();
      await work.delete(recursive: true).catchError((Object _) => work);
      rethrow;
    }
  }
}

const _source = r'''
import Foundation
import ScreenCaptureKit
import CoreGraphics
import AVFoundation

@available(macOS 15.0, *)
final class Recording: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var failed = false
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        print("MRA_RECORD_READY"); fflush(stdout)
    }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { done.signal() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        failed = true; done.signal(); exit(1)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { exit(1) }
}

@main struct Main {
    static func main() async {
        guard #available(macOS 15.0, *), CommandLine.arguments.count == 4,
              let index = Int(CommandLine.arguments[1]), index > 0,
              let fps = Int32(CommandLine.arguments[3]), fps > 0,
              CGPreflightScreenCaptureAccess() else { exit(1) }
        do {
            var count: UInt32 = 0
            guard CGGetActiveDisplayList(0, nil, &count) == .success else { exit(1) }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetActiveDisplayList(count, &ids, &count) == .success, index <= Int(count) else { exit(1) }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == ids[index - 1] }) else { exit(1) }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = CGDisplayPixelsWide(display.displayID)
            config.height = CGDisplayPixelsHigh(display.displayID)
            config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
            config.capturesAudio = false
            config.showsCursor = true
            let delegate = Recording()
            let outputConfig = SCRecordingOutputConfiguration()
            outputConfig.outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
            outputConfig.videoCodecType = .h264
            outputConfig.outputFileType = .mov
            let output = SCRecordingOutput(configuration: outputConfig, delegate: delegate)
            let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            let command = await Task.detached { readLine() }.value
            guard command == "stop" else { exit(1) }
            try await stream.stopCapture()
            let result = await Task.detached { delegate.done.wait(timeout: .now() + 10) }.value
            guard result == .success, !delegate.failed else { exit(1) }
        } catch { exit(1) }
    }
}
''';
