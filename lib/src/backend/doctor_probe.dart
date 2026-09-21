import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';

import '../protocol/protocol.dart';
import 'connection_uri.dart';

/// A separate read-only VM client; it never touches the session backend.
Future<Json> probeVmService(String input, DateTime deadline) async {
  Duration left() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) throw TimeoutException('Probe deadline');
    return value;
  }

  final uri = normalizeUri(input);
  final client = HttpClient();
  WebSocket? socket;
  VmService? service;
  var expired = false;
  try {
    final connecting = WebSocket.connect(uri.toString(), customClient: client);
    // A late successful handshake must not leave a connection behind.
    unawaited(
      connecting.then((value) {
        if (expired) unawaited(value.close());
      }, onError: (Object _) {}),
    );
    socket = await connecting.timeout(left());
    service = VmService(socket, socket.add);
    final version = await service.getVersion().timeout(left());
    final vm = await service.getVM().timeout(left());
    final bindings = <Json>[];
    for (final ref in vm.isolates ?? <IsolateRef>[]) {
      if (ref.id == null) continue;
      final isolate = await service.getIsolate(ref.id!).timeout(left());
      final extensions = (isolate.extensionRPCs ?? <String>[])
          .where((name) => name.startsWith('ext.flutter.marionette.'))
          .where(
            (name) =>
                RegExp(r'^ext\.flutter\.marionette\.[A-Za-z0-9_]+$')
                    .hasMatch(name),
          )
          .toList();
      if (extensions.isEmpty) continue;
      String? bindingVersion;
      if (extensions.contains('ext.flutter.marionette.getVersion')) {
        try {
          final response = await service
              .callServiceExtension(
                'ext.flutter.marionette.getVersion',
                isolateId: ref.id,
              )
              .timeout(left());
          final value = response.json?['version'];
          if (value is String &&
              RegExp(r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$')
                  .hasMatch(value)) {
            bindingVersion = value;
          }
        } on TimeoutException {
          rethrow;
        } catch (_) {
          /* A registered extension does not prove a version response. */
        }
      }
      bindings.add({
        'version': bindingVersion,
        'versionStatus': bindingVersion == null ? 'unknown' : 'observed',
        'registeredExtensions': extensions,
        'capabilityStatus': 'observedRegistrationsOnly',
      });
    }
    return {
      'vmServiceVersion': '${version.major}.${version.minor}',
      'bindingStatus': bindings.isEmpty ? 'unknown' : 'observed',
      'bindings': bindings,
    };
  } finally {
    expired = true;
    client.close(force: true);
    if (service != null) unawaited(service.dispose());
    if (socket != null) unawaited(socket.close());
  }
}
