import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:path/path.dart' as p;

/// SDK client -> product MCP stdio -> product CLI -> daemon -> real example app.
/// URI/raw logs stay private. The evidence transcript redacts the connect input.
Future<void> main() async {
  final uriFile = Platform.environment['MARIONETTE_TEST_VM_URI_FILE'];
  final root = Platform.environment['MARIONETTE_TEST_OUTPUT'];
  if (uriFile == null || root == null) {
    throw StateError(
      'Set MARIONETTE_TEST_VM_URI_FILE and MARIONETTE_TEST_OUTPUT',
    );
  }
  final uri = (await File(uriFile).readAsString()).trim();
  final evidence = await Directory('$root/evidence').create(recursive: true);
  final runtime = '$root/runtime';
  final cli = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'bin',
    'marionette_agent.dart',
  );
  final compiled = Platform.environment['MARIONETTE_TEST_MCP_EXECUTABLE'];
  final command = compiled == null
      ? [Platform.resolvedExecutable, cli]
      : [compiled];
  final process = await Process.start(
    command.first,
    [...command.skip(1), '--session=mcp-verify', 'mcp', '--tools=all'],
    environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime},
  );
  final diagnostics = process.stderr.transform(utf8.decoder).join();
  final client = MCPClient(
    Implementation(name: 'marionette-mcp-smoke', version: '1'),
  );
  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  final transcript = <Object?>[];
  bool closed = false;

  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<Map> call(
    String name, [
    Map<String, Object?> args = const {},
    String? error,
  ]) async {
    final result = await server.callTool(
      CallToolRequest(name: 'marionette_agent_$name', arguments: args),
    );
    final response = result.structuredContent!['response'] as Map;
    check(
      error == null
          ? result.isError == false
          : result.isError == true && response['error']['code'] == error,
      'Unexpected $name result: ${response['error']?['code']}',
    );
    transcript.add({
      'tool': name,
      'arguments': name == 'connect' ? {'uri': '<redacted-uri>'} : args,
      'structuredContent': result.structuredContent,
      'imageCount': result.content
          .where((part) => (part as Map)['type'] == 'image')
          .length,
    });
    if (name == 'screenshot') {
      final images = result.content
          .where((part) => (part as Map)['type'] == 'image')
          .toList();
      check(images.length == 1, 'Missing MCP screenshot image');
      final path = (response['data']['paths'] as List).single as String;
      final bytes = base64Decode((images.single as Map)['data'] as String);
      check(
        base64Encode(await File(path).readAsBytes()) == base64Encode(bytes),
        'Image does not match saved file',
      );
    }
    return response;
  }

  Map row(Map snapshot, String key) => (snapshot['data']['elements'] as List)
      .cast<Map>()
      .firstWhere((e) => e['key'] == key);

  try {
    final initialized = await server.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    server.notifyInitialized();
    transcript.add({'initialize': initialized});
    final names = <String>[];
    Cursor? cursor;
    do {
      final page = await server.listTools(ListToolsRequest(cursor: cursor));
      names.addAll(page.tools.map((tool) => tool.name));
      cursor = page.nextCursor;
    } while (cursor != null);
    transcript.add({'tools': names});
    await call('connect', {'uri': uri});
    final before = await call('snapshot');
    check(
      row(before, 'tap_result')['text'] == 'Tap count: 0',
      'Restart example to reset fixture',
    );
    await call('screenshot', {'path': '${evidence.path}/01-before.png'});
    final ref = row(before, 'tap_button')['ref'];
    await call('tap', {
      'target': {'ref': ref},
    });
    await call('tap', {
      'target': {'ref': ref},
    }, 'STALE_REF');
    final tapped = await call('snapshot');
    check(
      row(tapped, 'tap_result')['text'] == 'Tap count: 1',
      'Tap was not exactly once',
    );
    await call('fill', {
      'target': {'key': 'text_input'},
      'text': 'MCP verified',
    });
    await call('tap', {'x': 20, 'y': 80});
    final filled = await call('snapshot');
    check(
      '${row(filled, 'fill_result')['text']}'.contains('12'),
      'Input length did not become 12',
    );
    await call('screenshot', {'path': '${evidence.path}/02-filled.png'});
    await call('swipe', {
      'target': {'key': 'page_view'},
      'direction': 'left',
      'distance': 250,
    });
    await call('wait', {'milliseconds': 500});
    final swiped = await call('snapshot');
    check(
      '${row(swiped, 'page_result')['text']}'.contains('2'),
      'Page did not advance to 2',
    );
    await call('screenshot', {'path': '${evidence.path}/03-swiped.png'});
    await call('screenshot', {
      'path': '${evidence.path}/04-swiped.jpg',
      'format': 'jpeg',
      'quality': 85,
    });
    final independent = await Process.run(
      command.first,
      [...command.skip(1), '--json', '--session=mcp-verify', 'snapshot'],
      environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime},
    );
    check(
      independent.exitCode == 0,
      'Independent CLI could not share the session',
    );
    final observation = jsonDecode(independent.stdout as String) as Map;
    check(
      row(observation, 'tap_result')['text'] == 'Tap count: 1',
      'CLI/MCP session diverged',
    );
    transcript.add({
      'cli': '--json --session=mcp-verify snapshot',
      'response': observation,
    });
    await call('close');
    closed = true;
    await client.shutdown();
    check(await process.exitCode == 0, 'MCP did not exit cleanly on EOF');
    check((await diagnostics).isEmpty, 'Unexpected MCP diagnostics');
    for (var i = 0; i < 100 && File('$runtime/daemon.json').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    check(!File('$runtime/daemon.json').existsSync(), 'Daemon did not stop');
    final report = const JsonEncoder.withIndent('  ').convert(transcript);
    check(!report.contains(uri), 'Transcript contains authentication URI');
    await File('${evidence.path}/transcript.json').writeAsString(report);
    stdout.writeln(
      'PASS: ${names.length} tools; tap 0 -> 1; stale ref rejected; '
      'fill 12 characters; swipe page 1 -> 2; PNG/JPEG image content; shared CLI session; EOF/daemon cleanup.',
    );
  } finally {
    if (!closed && server.isActive) {
      try {
        await call('close');
      } catch (_) {
        /* Preserve original failure. */
      }
    }
    await client.shutdown();
    process.kill(ProcessSignal.sigkill);
  }
}
