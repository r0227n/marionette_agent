import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../daemon/client.dart';
import '../daemon/runtime.dart';
import '../diagnostics/diagnostic_logging.dart';
import '../mcp/server.dart';
import '../protocol/protocol.dart';
import '../workflow/model.dart';
import '../workflow/schema_catalog.dart';
import 'artifact_writer.dart';
import 'batch_loader.dart';
import 'common_options.dart';
import 'connection_state.dart';
import 'doctor.dart';
import 'input_file.dart';
import 'installer.dart';
import 'help.dart';
import 'skill_catalog.dart';
import 'observation_diff.dart';
import 'parser.dart';
import 'policy_file.dart';
import 'renderer.dart';
import 'workflow_loader.dart';

/// Handles parsing, one-shot IPC, and final stdout response, then returns exit code.
Future<int> runCli(
  List<String> args, {
  CliParser? parser,
  List<String>? launchCommand,
}) async {
  final started = DateTime.now();
  final elapsed = Stopwatch()..start();
  var json = false;
  var debug = false;
  final requestId = '$pid-${Random.secure().nextInt(1 << 32)}';
  DebugDiagnostics? diagnostics;
  var boundaries = false;
  String? session = const CommonOptions().session;
  Result result;
  bool workflow = false;
  var skills = false;
  int? diagnosticExitCode;
  String? workflowName;
  final cliParser = parser ?? CliParser();
  try {
    final invocation = cliParser.parse(
      args,
      onCommand: (command) {
        workflow = command == 'workflow';
        skills = command == 'skills';
      },
      onDebug: (value) => debug = value,
      onOutput: (name, useJson) {
        session = name;
        json = useJson;
      },
    );
    boundaries = invocation.options.contentBoundaries;
    workflow = invocation.command == 'workflow';
    json = invocation.json;
    session = invocation.resultSession;
    diagnostics = DebugDiagnostics(
      elapsed: elapsed,
      enabled: debug,
      requestId: requestId,
      session: session,
    );
    diagnostics.emit(DebugStage.cliParsed);
    if (invocation.command == 'mcp') {
      return await runMcpServer(
        invocation.options,
        (invocation.params['profiles'] as List).cast<String>(),
        launchCommand: launchCommand,
      );
    }
    final deadline = started.add(Duration(milliseconds: invocation.timeoutMs));
    if (invocation.command == 'skills') {
      final output = invocation.params['action'] == 'help'
          ? SkillsOutput({'help': skillsUsage}, skillsUsage)
          : SkillCatalog(
              await findSkillsDirectories(environment: cliParser.environment),
              deadline: deadline,
            ).run(invocation.params);
      diagnostics.emit(DebugStage.cliResult, code: 'OK');
      final rendered = output.render(json);
      stdout.write(rendered.endsWith('\n') ? rendered : '$rendered\n');
      return 0;
    }
    final policy = await loadPolicy(invocation.options, deadline);
    Json params = invocation.params;
    Json? localData;
    if (invocation.command == 'batch') {
      params = await loadBatch(params['path'] as String, deadline, cliParser);
    }
    if (workflow) {
      if (params['action'] == 'schema') {
        localData = {
          'workflowSchemaVersion': 1,
          'action': params['schemaAction'],
          'schema': workflowSchema(params['schemaAction'] as String?),
        };
      } else {
        final document = await loadWorkflowFile(
          params['path'] as String,
          params['format'] as String,
          deadline,
        );
        workflowName = workflowNameFrom(document);
        WorkflowPlan.decode(document, bind: false);
        final inputs = params['inputsPath'] == null
            ? <String, Object?>{}
            : await loadWorkflowFile(
                params['inputsPath'] as String,
                params['inputsFormat'] as String,
                deadline,
              );
        final bind = params['bind'] == true;
        final plan = WorkflowPlan.decode(document, inputs: inputs, bind: bind);
        if (params['action'] == 'validate') {
          localData = {
            'workflow': plan.name,
            'format': params['format'],
            'stepCount': plan.steps.length,
            'mode': bind ? 'bound' : 'template',
            'requiredInputs': plan.requiredInputs,
            'inputsValidated': bind,
          };
        }
        params = {'workflow': document, 'inputs': inputs};
      }
    }
    if (workflow && !deadline.isAfter(DateTime.now())) {
      throw const AgentError(
        'TIMEOUT',
        'Workflow validation deadline exceeded',
      );
    }
    if (['install', 'upgrade'].contains(invocation.command)) {
      result = Result.success(
        null,
        await installCli(params, invocation.command, deadline),
      );
    } else if (invocation.command == 'device') {
      try {
        result = Result.success(null, {
          'devices': await listDevices(params['platform'] as String, deadline),
        });
      } on PlatformException catch (error) {
        throw AgentError(error.code, error.message);
      }
    } else if (invocation.command == 'doctor') {
      final data = await Doctor(namespace: invocation.options.namespace).run(
        deadline,
        probeUri: params['probeUri'] as String?,
        quick: params['quick'] == true,
        offline: params['offline'] == true,
        fix: params['fix'] == true,
      );
      diagnosticExitCode = data['exitCode'] as int;
      result = Result.success(null, data);
    } else if (localData != null) {
      result = Result.success(null, localData);
    } else if (invocation.command == 'help') {
      result = Result.success(null, {'help': cliParser.usage});
    } else if (invocation.command == 'version') {
      result = Result.success(null, {'version': version});
    } else {
      final baseline = invocation.command == 'diff'
          ? await readInputFile(params['baseline'] as String, deadline)
          : null;
      diagnostics.emit(DebugStage.runtimePrepare);
      final runtime = await RuntimeDirectory.prepare(
        namespace: invocation.options.namespace,
      );
      final client = DaemonClient(
        runtime,
        launchCommand: launchCommand,
        idleTimeoutMs: invocation.options.idleTimeoutMs,
      );
      var command = invocation.command;
      var requestParams = params;
      if (invocation.options.restore != null) {
        final uri = await loadConnectionState(
          invocation.options.restore!,
          deadline,
        );
        final connected = await client.send(
          Request(
            requestId: requestId,
            session: invocation.session,
            command: 'connect',
            params: {'uri': uri},
            deadline: deadline,
          ),
        );
        if (connected.error != null) throw connected.error!;
      }
      if (command == 'state') {
        if (params['action'] == 'load') {
          command = 'connect';
          requestParams = {
            'uri': await loadConnectionState(
              params['path'] as String,
              deadline,
            ),
          };
        } else {
          requestParams = {'action': 'export'};
        }
      }
      result = await client.send(
        Request(
          requestId: requestId,
          debug: debug,
          policy: policy,
          session: invocation.session,
          command: command == 'diff'
              ? (params['action'] == 'snapshot'
                    ? 'diff-snapshot'
                    : 'screenshot')
              : command,
          params: command == 'diff' ? {} : requestParams,
          maxOutput: command == 'diff' ? null : invocation.options.maxOutput,
          outputJson: invocation.json,
          deadline: deadline,
        ),
      );
      if (result.error?.code == 'CONFIRMATION_REQUIRED' &&
          invocation.options.confirmInteractive &&
          stdin.hasTerminal) {
        final id = result.error!.details!['confirmationId'] as String;
        stderr.write('Confirm ${result.error!.details!['command']}? [y/N] ');
        String answer;
        try {
          answer = await stdin
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(deadline.difference(DateTime.now()));
        } catch (_) {
          answer = '';
        }
        result = await client.send(
          Request(
            requestId: requestId,
            session: invocation.session,
            command: answer.trim().toLowerCase() == 'y' ? 'confirm' : 'deny',
            params: {'id': id},
            deadline: deadline,
            maxOutput: invocation.options.maxOutput,
            outputJson: json,
            debug: debug,
          ),
        );
      }
      if (invocation.command == 'state' &&
          params['action'] == 'save' &&
          result.error == null) {
        result = Result.success(
          session,
          await saveConnectionState(
            params['path'] as String,
            result.data!,
            deadline,
          ),
        );
      }
      if (baseline != null && result.error == null) {
        result = Result.success(
          session,
          await compareObservation(params, baseline, result.data!, deadline),
        );
      }
      if (invocation.command == 'screenshot' && result.error == null) {
        result = Result.success(
          session,
          await saveScreenshots(
            result.data!,
            invocation.params['path'] as String?,
            deadline,
            format: invocation.options.screenshotFormat,
            quality: invocation.options.screenshotQuality,
            screenshotDir: invocation.options.screenshotDir,
          ),
        );
      }
    }
  } on AgentError catch (error) {
    result = Result.failure(
      session,
      workflow && error.details == null
          ? workflowError(error, name: workflowName)
          : error,
    );
  } catch (_) {
    result = Result.failure(
      session,
      const AgentError('INTERNAL_ERROR', 'CLI failed'),
    );
  }
  (diagnostics ??
          DebugDiagnostics(
            elapsed: elapsed,
            enabled: debug,
            requestId: requestId,
            session: session,
          ))
      .emit(DebugStage.cliResult, code: result.error?.code ?? 'OK');
  if (skills && result.error != null) {
    final message = result.error!.message;
    if (json) {
      stdout.writeln(jsonEncode({'success': false, 'error': message}));
    } else {
      stderr.writeln(message);
    }
    return 1;
  }
  stdout.writeln(render(result, json: json, contentBoundaries: boundaries));
  if (!json && result.error?.code == 'INVALID_ARGUMENT') {
    stdout.writeln(cliParser.usage);
  }
  return diagnosticExitCode ?? result.exitCode;
}
