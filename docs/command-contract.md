# Command implementation contract

[日本語](ja/command-contract.ja.md) · [Documentation index](README.md)

This document describes boundaries for CLI handlers and backend adapters. See the [site](https://r0227n.github.io/marionette_agent/en/) for usage, [SPEC](SPEC.md) for the product contract, and [ARCHITECTURE](ARCHITECTURE.md) for dependency direction. Read versions from [pubspec](../pubspec.yaml) and [protocol constants](../lib/src/protocol/protocol.dart) rather than duplicating them here.

<a id="boundaries"></a>
## Boundaries and registration

```text
CliParser / CliCommand
  -> DaemonClient
  -> SessionManager
  -> CommandRegistry
  -> CommandContext
  -> Backend
```

Define syntax in `cli/commands/` and the catalog, with shared types in `cli/command.dart`. Register ordinary handlers under the same name in `coreCommands()`. Decode converts ArgResults into string-keyed JSON params. Because IPC can bypass the CLI, handlers also validate allowed fields, types, required fields, and exclusions. Unknown fields must not be ignored. Common options belong in the root parser’s `cli/common_options.dart`; selectors use `addSelectorOptions`, `parseTarget`, and shared decoding.

Internal handlers directly import necessary backend/protocol/commands/snapshot definitions, without depending on CLI/args or the public barrel. External composition uses `marionette_agent.dart`. Restrict upstream `marionette_mcp/src/` imports to `backend/marionette_backend.dart`; handlers must not consume raw upstream maps or connector exceptions. See [probe_cli.dart](../integration_test/support/probe_cli.dart) for an executable registration example.

Recording delegates from the shared session queue to RecordService and util. OS screen recording can run without a VM Service connection; Flutter rendering recording requires one. Platform operations and shutdown signals belong in util and do not change operation refs or connection generations.

<a id="validation"></a>
## Validate before mutation

Validate every parameter before entering a mutation path. RefQuery and SelectorQuery are external targets; ObservedQuery is internal and retains find selection attributes. Do not construct ObservedQuery from external JSON. Do not mix refs/selectors/coordinates; reject empty selectors.

Points must be finite and nonnegative; swipe distance must be finite and positive, default 200. Coordinate swipe endpoints must differ. Direction describes finger movement. Wait polling is an integer from 50–1,000 ms, default 100. Additional operations follow the [provider contract](cli-parity.md), checking capabilities before acting.

<a id="context"></a>
## CommandContext and dispatch count

Access session state through [CommandContext](../lib/src/commands/command_context.dart).

| API | Contract |
| --- | --- |
| snapshot | Observe, replace the public snapshot, and issue new refs |
| observeTarget / resolveRead | Read through shared uniqueness/stale validation |
| performTarget | Reobserve and validate attributes; expire refs and call back once |
| performTargets | Validate multiple targets in one observation; expire refs and call back once |
| uniqueTarget | Retain a unique matcher and selection attributes in ObservedQuery |
| performCoordinates | Expire refs before explicit coordinate operations |
| performEffect | Record dispatch of a non-UI side effect while preserving refs |
| read / check | Verify deadline, connection generation, and parent stop state across awaits and before publishing |
| deadline / session | Shared absolute deadline and session name; do not expose the URI |

One Execution sends at most one UI mutation; callbacks call a backend primitive exactly once. Handlers must not implement their own retry, queue, session creation, ref storage, or connection disposal. Success means backend completion, not a verified visual state. Ordinary mutations return requiresSnapshot:true.

<a id="execution"></a>
## Sessions, deadlines, and targets

SessionManager serializes each session, includes queue time in the deadline, and never executes an expired queued request later. Pre-dispatch rejection is not_sent, confirmed mutation failure is failed, and post-dispatch timeout/disconnection/unclassified failure is unknown. A read timeout/disconnection is not_sent but still discards connection and refs. Late completion of old Futures cannot change a reconnected session.

SnapshotService increases generations and ref numbers across the daemon without reusing numbers between sessions. Hidden elements receive reason:not_visible; elements without a safe unique selector receive reason:no_unique_supported_selector. Neither receives a ref. Binding 0.6.0 supports key/text/type action selectors, not identifier. Verified text origins are Text/RichText/EditableText/TextField/TextFormField.

Reobserve before mutation. Zero matches mean STALE_REF for refs or TARGET_NOT_FOUND for explicit selectors. Multiple matches, including hidden elements, mean AMBIGUOUS_TARGET. Changed ref attributes mean STALE_REF; a unique hidden element or unverified text origin means UNRESOLVABLE_TARGET. Observation and mutation are not atomic, and refs do not fall back to coordinates.

<a id="adapter"></a>
## Adapters, images, and logs

Use typed Backend primitives and capability interfaces. Validate upstream Success and response structure in the adapter. Connection_uri normalizes HTTP(S) into WS(S), preserves path/query for the connection, and exposes only host/port in status. Scroll uses the swipe primitive and adds command:scroll to its result.

Screenshot passes base64 PNG from the daemon to the CLI, where [artifact_writer.dart](../lib/src/cli/artifact_writer.dart) validates it, converts to the requested format, and saves exclusively. See the [image contract](cli-reference.md#capture) for PNG/JPEG quality, paths, and failure cleanup. Handlers must not introduce separate persistence rules; capture through saving shares the original deadline.

Logs returns entries, nullable configured, and limitation when necessary. False means unconfigured was observed; null means the backend cannot distinguish unconfigured from empty. App logs are stdout result data, not diagnostics.

AgentError returns safe code/message/hint/details/outcome. Exit codes are documented in the [output reference](https://r0227n.github.io/marionette_agent/en/reference/output/). Diagnostics send INFO and above to stderr, redact authenticated URIs, escape newlines, and omit raw errors, stack traces, and input values.

<a id="workflow"></a>
## Reusing workflow and wait handlers

Workflow holds one queue entry and creates an Execution/CommandContext per step. Steps must not recursively call SessionManager.handle. Snapshot/tap/fill/swipe/scroll/wait reuse ordinary handlers; workflow adds progress without changing outcomes. See the [workflow reference](workflow-file-spec.md).

Standalone and workflow wait share handleWait. Only workflow supplies the earlier overall/step deadline. After validating all inputs and selector capabilities, the handler polls inspect serially through the read path without sending mutations. Success preserves refs; timeout/disconnection during reads discards the connection generation.

<a id="verification"></a>
## Verification

Run formatting, analysis, and relevant tests in the CLI package, then the full suite before handoff. Snapshot/session/transport, feature_commands/swipe/wait, artifact_writer, and workflow_execution tests cover resolution, dispatch, late completion, and persistence boundaries.

```sh
dart format .
dart analyze
dart test
```

CLI feature changes also require launching the example in iOS Simulator and checking both product CLI responses and actual screen changes. Update documentation according to the [bilingual policy](documentation.md).
