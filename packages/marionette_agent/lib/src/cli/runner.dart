import 'dart:io';
import 'dart:math';

import '../daemon/client.dart';
import '../daemon/runtime.dart';
import '../diagnostics/diagnostic_logging.dart';
import '../protocol/protocol.dart';
import 'parser.dart';
import 'doctor.dart';
import 'common_options.dart';
import 'artifact_writer.dart';
import 'renderer.dart';
import 'workflow_loader.dart';
import '../workflow/model.dart';
import '../workflow/schema_catalog.dart';

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
  int? diagnosticExitCode;
  String? workflowName;
  final cliParser = parser ?? CliParser();
  try {
    final invocation = cliParser.parse(
      args,
      onCommand: (command) => workflow = command == 'workflow',
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
    final deadline = started.add(Duration(milliseconds: invocation.timeoutMs));
    Json params = invocation.params;
    Json? localData;
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
    if (invocation.command == 'doctor') {
      final data = await Doctor().run(
        deadline,
        probeUri: params['probeUri'] as String?,
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
      diagnostics.emit(DebugStage.runtimePrepare);
      final runtime = await RuntimeDirectory.prepare();
      result =
          await DaemonClient(
            runtime,
            launchCommand: launchCommand,
            idleTimeoutMs: invocation.options.idleTimeoutMs,
          ).send(
            Request(
              requestId: requestId,
              debug: debug,
              session: invocation.session,
              command: invocation.command,
              params: params,
              maxOutput: invocation.options.maxOutput,
              outputJson: invocation.json,
              deadline: started.add(
                Duration(milliseconds: invocation.timeoutMs),
              ),
            ),
          );
      if (invocation.command == 'screenshot' && result.error == null) {
        result = Result.success(
          session,
          await saveScreenshots(
            result.data!,
            invocation.params['path'] as String?,
            started.add(Duration(milliseconds: invocation.timeoutMs)),
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
  stdout.writeln(render(result, json: json, contentBoundaries: boundaries));
  if (!json && result.error?.code == 'INVALID_ARGUMENT') {
    stdout.writeln(cliParser.usage);
  }
  return diagnosticExitCode ?? result.exitCode;
}
