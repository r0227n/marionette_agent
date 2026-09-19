import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:image/image.dart' as image;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/mcp/catalog.dart';
import 'package:marionette_agent/src/mcp/executor.dart';
import 'package:marionette_agent/src/protocol/protocol.dart' as agent;
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';

void main() {
  final cli = File('bin/marionette_agent.dart').absolute.path;

  test(
    'MCP startup validates profiles and unsupported interactive options',
    () {
      final parser = CliParser(environment: {});
      expect(parser.parse(['mcp']).params['profiles'], ['core']);
      expect(
        parser.parse(['mcp', '--tools=core,inspect,core']).params['profiles'],
        ['core', 'inspect'],
      );
      for (final args in [
        ['mcp', '--tools='],
        ['mcp', '--tools=missing'],
        ['mcp', '--tools=core,'],
        ['mcp', '--tools=all', '--tools=core'],
        ['mcp', 'extra'],
        ['mcp', '--confirm-interactive'],
        ['mcp', '--restore=state.json'],
      ]) {
        expect(
          () => parser.parse(args),
          throwsA(isA<agent.AgentError>()),
          reason: '$args',
        );
      }
      expect(parser.parse(['mcp', '--help']).command, 'help');
    },
  );

  test(
    'typed tools retain literal inputs and reject MCP stdin as file input',
    () {
      final tools = {for (final tool in mcpToolCatalog()) tool.name: tool};
      const literal =
          '--session=other\n'
          r'$(touch /tmp/never-run) "秘密"';
      final parsed = CliParser(environment: {}).parse(
        tools['fill']!.arguments({
          'target': {'key': '--json'},
          'text': literal,
        }, const CommonOptions(session: 'mcp')),
      );
      expect(parsed.session, 'mcp');
      expect(parsed.params['key'], '--json');
      expect(parsed.params['input'], literal);
      for (final name in ['batch', 'workflow_run', 'workflow_validate']) {
        expect(
          () => tools[name]!.arguments({'path': '-'}, const CommonOptions()),
          throwsA(isA<agent.AgentError>()),
        );
      }
      final shot = CliParser(environment: {}).parse(
        tools['screenshot']!.arguments({
          'format': 'jpeg',
          'quality': 30,
          'path': '-image.jpg',
        }, const CommonOptions(screenshotFormat: ScreenshotFormat.png)),
      );
      expect(shot.params['path'], '-image.jpg');
      expect(shot.options.screenshotQuality, 30);
    },
  );

  test('extended tool schemas map to valid existing CLI invocations', () {
    final tools = {for (final tool in mcpToolCatalog()) tool.name: tool};
    final samples = <String, Map<String, Object?>>{
      'launch': {
        'project': '../../example',
        'platform': 'ios',
        'timeoutMs': 120000,
        'deviceType': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',
        'runtime': 'com.apple.CoreSimulator.SimRuntime.iOS-26-2',
      },
      'swipe': {'startX': 20, 'startY': 50, 'endX': 200, 'endY': 50},
      'wait': {
        'target': {'text': 'done'},
        'state': 'exists',
        'pollIntervalMs': 100,
      },
      'get_value': {
        'target': {'key': 'input'},
      },
      'keyboard_press': {'text': 'ENTER'},
      'clipboard_write': {'text': '--json'},
      'drag': {'from': '@e1', 'to': '@e2'},
      'workflow_run': {'path': 'test.yaml', 'inputs': 'inputs.json'},
      'workflow_validate': {'path': 'test.yaml', 'checkInputs': true},
      'record_start': {'path': 'movie.mp4', 'platform': 'flutter', 'fps': 10},
      'record_restart': {
        'path': 'movie.mp4',
        'platform': 'ios',
        'device': '00000000-0000-0000-0000-000000000001',
      },
      'confirm': {'id': '0123456789abcdef0123456789abcdef'},
    };
    for (final entry in samples.entries) {
      final tool = tools[entry.key]!;
      expect(
        tool.tool.inputSchema.validate(entry.value),
        isEmpty,
        reason: entry.key,
      );
      final invocation = CliParser(environment: {}).parse(
        tool.arguments(
          entry.value,
          const CommonOptions(
            namespace: 'mcp',
            actionPolicy: 'policy.json',
            confirmActions: 'tap',
          ),
        ),
      );
      expect(invocation.command, tool.command.first);
      expect(invocation.options.namespace, 'mcp');
      expect(invocation.options.actionPolicy, 'policy.json');
      expect(invocation.options.confirmActions, 'tap');
    }
  });

  group('real stdio server with SDK client and daemon', () {
    late Directory temp;
    late DaemonServer daemon;
    late Future<void> serving;
    late Process process;
    late Future<String> diagnostics;
    late MCPClient client;
    late ServerConnection server;
    late _InputBackend backend;
    late List<int> png;

    Future<CallToolResult> call(
      String name, [
      Map<String, Object?> arguments = const {},
    ]) => server.callTool(
      CallToolRequest(name: 'marionette_agent_$name', arguments: arguments),
    );
    Map response(CallToolResult result) =>
        result.structuredContent!['response'] as Map;

    setUp(() async {
      temp = await Directory('/tmp').createTemp('mcp-test-');
      png = image.encodePng(image.Image(width: 3, height: 2));
      backend = _InputBackend()
        ..elements = [
          ElementInfo(key: 'button', type: 'Button', visible: true),
          ElementInfo(key: 'input', type: 'TextField', visible: true),
          ElementInfo(key: 'duplicate', type: 'Button'),
          ElementInfo(key: 'duplicate', type: 'Button'),
        ]
        ..screenshots = [base64Encode(png)];
      final runtime = await RuntimeDirectory.prepare(
        directory: '${temp.path}/runtime',
      );
      daemon = DaemonServer(
        runtime,
        SessionManager(() => backend, coreCommands()),
      );
      serving = daemon.run();
      while (!File(runtime.metadata).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      process = await Process.start(
        Platform.resolvedExecutable,
        [cli, '--session=mcp-test', 'mcp', '--tools=all'],
        environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
      );
      diagnostics = process.stderr.transform(utf8.decoder).join();
      client = MCPClient(Implementation(name: 'mcp-test', version: '1'));
      server = client.connectServer(
        stdioChannel(input: process.stdout, output: process.stdin),
      );
      final initialized = await server.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      expect(initialized.serverInfo.name, 'marionette-agent');
      expect(initialized.capabilities.tools, isNotNull);
      server.notifyInitialized();
    });
    tearDown(() async {
      await client.shutdown();
      try {
        expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
      } finally {
        process.kill(ProcessSignal.sigkill);
        await daemon.close();
        await serving;
        await temp.delete(recursive: true);
      }
      expect(await diagnostics, isEmpty);
    });

    test('paginated discovery, ping and protocol errors', () async {
      final names = <String>[];
      Cursor? cursor;
      do {
        final page = await server.listTools(ListToolsRequest(cursor: cursor));
        expect(page.tools.length, lessThanOrEqualTo(20));
        names.addAll(page.tools.map((tool) => tool.name));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(names.toSet().length, names.length);
      expect(
        names,
        containsAll([
          'marionette_agent_connect',
          'marionette_agent_record_start',
          'marionette_agent_workflow_run',
        ]),
      );
      await server.ping();
      await expectLater(
        server.listTools(ListToolsRequest(cursor: Cursor('-1'))),
        throwsA(isA<RpcException>()),
      );
      await expectLater(call('not_a_tool'), throwsA(isA<RpcException>()));
      expect(
        (await call('tools_profiles')).structuredContent!['activeProfiles'],
        ['all'],
      );
    });

    test(
      'connect, refs, one-shot mutation, literal fill, errors and images',
      () async {
        expect(
          (await call('connect', {
            'uri': 'http://localhost:1/auth-secret/',
          })).isError,
          false,
        );
        final snapshot = response(await call('snapshot'));
        expect(snapshot['session'], 'mcp-test');
        final elements = (snapshot['data'] as Map)['elements'] as List;
        final ref =
            (elements.firstWhere((e) => e['key'] == 'button') as Map)['ref'];
        expect(
          (await call('tap', {
            'target': {'ref': ref},
          })).isError,
          false,
        );
        final stale = await call('tap', {
          'target': {'ref': ref},
        });
        expect(stale.isError, true);
        expect(response(stale)['error']['code'], 'STALE_REF');
        expect(response(stale)['error']['outcome'], 'not_sent');
        expect(backend.calls.where((c) => c == 'tap'), hasLength(1));
        const literal =
            '--json\n'
            r'$(do-not-execute) "日本語"';
        expect(
          (await call('fill', {
            'target': {'key': 'input'},
            'text': literal,
          })).isError,
          false,
        );
        expect(backend.input, literal);
        final ambiguous = await call('tap', {
          'target': {'key': 'duplicate'},
        });
        expect(response(ambiguous)['error']['code'], 'AMBIGUOUS_TARGET');
        expect((await call('snapshot', {'session': 'other'})).isError, true);
        final shot = await call('screenshot', {
          'path': '${temp.path}/shot.png',
        });
        expect(shot.isError, false);
        expect(shot.content.whereType<Map>().last['type'], 'image');
        expect(base64Decode((shot.content.last as Map)['data'] as String), png);
        expect(await File('${temp.path}/shot.png').readAsBytes(), png);
        final jpeg = await call('screenshot', {
          'path': '${temp.path}/shot.jpg',
          'format': 'jpeg',
          'quality': 50,
        });
        expect(jpeg.isError, false);
        expect((jpeg.content.last as Map)['mimeType'], 'image/jpeg');
        expect(
          (await call('screenshot', {'path': '${temp.path}/shot.png'})).isError,
          true,
        );
        expect((await call('close')).isError, false);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('schema errors do not execute or echo private input', () async {
      final result = await call('fill', {
        'target': {'key': 'input'},
        'text': ['private-secret'],
      });
      expect(result.isError, true);
      expect(jsonEncode(result), isNot(contains('private-secret')));
      expect(backend.calls, isEmpty);
      expect(
        (await call('tap', {
          'target': {'key': 'button', 'text': 'private-secret'},
        })).isError,
        true,
      );
      expect(
        (await call('fill', {
          'target': {'key': 'input'},
          'text': 'x',
          'extraArgs': ['--help'],
        })).isError,
        true,
      );
    });

    test(
      'timeout retains unknown outcome and never retries mutation',
      () async {
        await call('connect', {'uri': 'http://localhost:1/'});
        backend.hooks['tap'] = () =>
            Future<void>.delayed(const Duration(milliseconds: 500));
        final result = await call('tap', {
          'target': {'key': 'button'},
          'timeoutMs': 100,
        });
        expect(result.isError, true);
        expect(response(result)['error']['code'], 'TIMEOUT');
        expect(response(result)['error']['outcome'], 'unknown');
        expect(backend.calls.where((c) => c == 'tap'), hasLength(1));
      },
    );
  });

  test(
    'default profile hides extended tools and EOF exits without a daemon',
    () async {
      final temp = await Directory('/tmp').createTemp('mcp-core-');
      final process = await Process.start(
        Platform.resolvedExecutable,
        [cli, 'mcp'],
        environment: {'MARIONETTE_AGENT_RUNTIME_DIR': '${temp.path}/runtime'},
      );
      final errors = process.stderr.transform(utf8.decoder).join();
      final client = MCPClient(Implementation(name: 'core-test', version: '1'));
      final server = client.connectServer(
        stdioChannel(input: process.stdout, output: process.stdin),
      );
      try {
        await server.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.v2024_11_05,
            capabilities: client.capabilities,
            clientInfo: client.implementation,
          ),
        );
        server.notifyInitialized();
        final listed = await server.listTools();
        expect(
          listed.tools.map((tool) => tool.name),
          isNot(contains('marionette_agent_record_start')),
        );
        await expectLater(
          server.callTool(
            CallToolRequest(
              name: 'marionette_agent_record_start',
              arguments: {},
            ),
          ),
          throwsA(isA<RpcException>()),
        );
        expect(Directory('${temp.path}/runtime').existsSync(), false);
        await client.shutdown();
        expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect(await errors, isEmpty);
      } finally {
        process.kill(ProcessSignal.sigkill);
        await client.shutdown();
        await temp.delete(recursive: true);
      }
    },
  );

  test('executor startup failure is not_sent and active children stop on close', () async {
    final missing = McpExecutor(launchCommand: ['/definitely-missing/mcp-cli']);
    final failed = await missing.run(['--json', 'snapshot']);
    expect((failed.response['error'] as Map)['outcome'], 'not_sent');
    final temp = await Directory('/tmp').createTemp('mcp-exec-');
    final fixture = File('${temp.path}/child.dart');
    await fixture.writeAsString(
      "import 'dart:io'; Future<void> main() async { File('${temp.path}/pid').writeAsStringSync('\$pid'); await Future<void>.delayed(const Duration(minutes: 1)); }",
    );
    final executor = McpExecutor(
      launchCommand: [Platform.resolvedExecutable, fixture.path],
    );
    try {
      final result = executor.run(['--json', 'snapshot']);
      while (!File('${temp.path}/pid').existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await executor.close();
      expect(((await result).response['error'] as Map)['outcome'], 'unknown');
    } finally {
      await executor.close();
      await temp.delete(recursive: true);
    }
  });

  test(
    'invalid child envelopes are unknown and parser failures preserve session',
    () async {
      final temp = await Directory('/tmp').createTemp('mcp-invalid-');
      final fixture = File('${temp.path}/child.dart');
      await fixture.writeAsString(
        "void main() { print('{\"schemaVersion\":999,\"private\":\"secret\"}'); }",
      );
      final executor = McpExecutor(
        launchCommand: [Platform.resolvedExecutable, fixture.path],
      );
      try {
        final rejected = await executor.run([
          '--json',
          '--session=selected',
          'tap',
        ]);
        expect(rejected.response['session'], 'selected');
        expect((rejected.response['error'] as Map)['outcome'], 'not_sent');
        final malformed = await executor.run([
          '--json',
          '--session=selected',
          'snapshot',
        ]);
        expect((malformed.response['error'] as Map)['outcome'], 'unknown');
        expect(jsonEncode(malformed.response), isNot(contains('secret')));
      } finally {
        await executor.close();
        await temp.delete(recursive: true);
      }
    },
  );
}

class _InputBackend extends FakeBackend {
  String? input;
  @override
  Future<void> fill(Selector selector, String text) async {
    input = text;
    await super.fill(selector, text);
  }
}
