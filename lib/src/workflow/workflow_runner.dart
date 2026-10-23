import 'dart:async';

import '../artifacts/artifact_writer.dart';
import '../artifacts/screenshot_options.dart';

import '../commands/command_context.dart';
import '../commands/registry.dart';
import '../protocol/protocol.dart';
import '../session/session.dart';
import '../snapshot/snapshot_service.dart';
import 'model.dart';

/// Parent lifetime is pinned to the connection generation acquired by this queue entry.
/// Each child retains its own one-mutation guard and error classification.
class WorkflowExecution {
  WorkflowExecution(this.request, this.session, this.snapshots, this.commands)
    : epoch = session.epoch;
  final Request request;
  final Session session;
  final SnapshotService snapshots;
  final CommandRegistry commands;
  final int epoch;
  bool stopped = false;
  int completed = 0;
  WorkflowStep? activeStep;
  int? activeIndex;
  Json? finalSnapshot;
  final screenshots = <Json>[];
  void check() {
    if (stopped || session.epoch != epoch) {
      throw const AgentError('CONNECTION_LOST', 'Workflow generation retired');
    }
    request.checkDeadline();
  }

  void retire() {
    stopped = true;
    if (session.epoch == epoch) session.discard();
  }

  Future<Json> run() async {
    String? name = workflowNameFrom(request.params['workflow']);
    try {
      if (request.params.keys.any(
            (key) => !{'workflow', 'inputs', 'screenshotOptions'}.contains(key),
          ) ||
          !request.params.containsKey('workflow') ||
          !request.params.containsKey('inputs')) {
        invalid('Invalid workflow request');
      }
      final plan = WorkflowPlan.decode(
        request.params['workflow'],
        inputs: request.params['inputs'],
      );
      final output = ScreenshotOptions.decode(
        request.params['screenshotOptions'],
      );
      for (final step in plan.steps.where((s) => s.action == 'screenshot')) {
        output.validateDestination(step.params['path']);
      }
      name = plan.name;
      check();
      Execution(
        request,
        session,
        initialEpoch: epoch,
        parentCheck: check,
      ).requireConnected();
      // All capability checks precede the first UI read or mutation.
      for (final step in plan.steps) {
        if (step.selector != null &&
            !session.backend!.selectors.contains(step.selector!.kind)) {
          throw const AgentError(
            'UNSUPPORTED_CAPABILITY',
            'Unsupported workflow selector',
          );
        }
      }
      for (var i = 0; i < plan.steps.length; i++) {
        final step = plan.steps[i];
        activeStep = step;
        activeIndex = i + 1;
        check();
        final conditionEnd = DateTime.now().add(
          Duration(milliseconds: step.timeoutMs),
        );
        final deadline =
            step.action == 'wait' && conditionEnd.isBefore(request.deadline)
            ? conditionEnd
            : request.deadline;
        final child = Execution(
          Request(
            requestId: request.requestId,
            session: request.session,
            command: step.action,
            params: step.params,
            deadline: deadline,
          ),
          session,
          initialEpoch: epoch,
          parentCheck: check,
          onRetire: retire,
        );
        final context = CommandContext(child, snapshots);
        final result = await child.bound(() async {
          final data = await commands.dispatch(
            context,
            step.action,
            step.params,
          );
          if (step.action != 'screenshot') return data;
          check();
          return saveScreenshots(
            data,
            step.params['path'] as String?,
            deadline,
            format: output.format,
            quality: output.quality,
            screenshotDir: output.directory,
          );
        });
        check();
        completed++;
        if (step.action == 'screenshot') {
          screenshots.add({'stepId': step.id, ...result});
        } else if (step.action == 'snapshot') {
          finalSnapshot = result;
        } else if (step.action != 'wait') {
          finalSnapshot = null;
        }
      }
      stopped = true;
      return {
        'workflow': name,
        'completedSteps': completed,
        if (screenshots.isNotEmpty) 'screenshots': screenshots,
        'requiresSnapshot': finalSnapshot == null,
        if (finalSnapshot != null) 'finalSnapshot': finalSnapshot,
      };
    } on AgentError catch (error) {
      if (error.code == 'TIMEOUT' || error.code == 'CONNECTION_LOST') retire();
      stopped = true;
      throw workflowError(
        error,
        name: name,
        completed: completed,
        index: activeIndex,
        step: activeStep,
        screenshots: screenshots,
      );
    } catch (_) {
      stopped = true;
      throw workflowError(
        const AgentError('INTERNAL_ERROR', 'Workflow failed'),
        name: name,
        completed: completed,
        index: activeIndex,
        step: activeStep,
        screenshots: screenshots,
      );
    }
  }
}
