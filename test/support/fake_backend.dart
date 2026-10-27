import 'dart:convert';
import 'dart:typed_data';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';

/// Controllable backend for downstream command and concurrency tests.
/// Hooks run before completion, allowing barriers, failures and late responses.
class FakeBackend implements Backend, ScreenCapturer {
  List<ElementInfo> elements = [];
  List<String> screenshots = [];
  LogBatch logs = const LogBatch([], configured: true);
  final calls = <String>[];
  final hooks = <String, Future<void> Function()>{};
  bool connected = false;
  int active = 0, maxActive = 0;
  @override
  Set<SelectorKind> selectors = {
    SelectorKind.key,
    SelectorKind.text,
    SelectorKind.type,
  };
  Future<void> _run(String name) async {
    calls.add(name);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (name != 'connect' &&
          name != 'disconnect' &&
          name != 'captureScreen' &&
          !connected) {
        throw const AgentError('CONNECTION_LOST', 'Fake connection lost');
      }
      await hooks[name]?.call();
    } finally {
      active--;
    }
  }

  @override
  Future<void> connect(Uri uri) async {
    await _run('connect');
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    await _run('disconnect');
  }

  @override
  Future<void> checkConnection() => _run('checkConnection');
  @override
  Future<List<ElementInfo>> inspect() async {
    await _run('inspect');
    return List.of(elements);
  }

  @override
  Future<void> tap(TapTarget target) => _run('tap');
  @override
  Future<void> fill(Selector selector, String text) => _run('fill');
  @override
  Future<void> swipe(SwipeGesture gesture) => _run('swipe');
  @override
  Future<CapturedScreen> capture(String device, DateTime deadline) async {
    await _run('captureScreen');
    return CapturedScreen(
      screenshots.isEmpty ? Uint8List(0) : base64Decode(screenshots.first),
      source: 'android-uiautomator',
      device: 'test-device',
      display: 0,
    );
  }

  @override
  Future<LogBatch> readLogs() async {
    await _run('readLogs');
    return logs;
  }
}
