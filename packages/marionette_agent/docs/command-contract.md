# A06: Command Implementation Contract

This document is a handoff note for extending with A07/B01+ on top of the shared A01–A06 foundation. SPEC is in [SPEC](../../../SPEC.md), architecture in [ARCHITECTURE](../../../ARCHITECTURE.md), and progress in [todo](../../../todo.md).

## Entry and Existing Packages

Individual commands must import `package:marionette_agent/marionette_agent.dart`. Only `lib/src/backend/marionette_backend.dart` imports upstream `marionette_mcp/src/`.

- `args`: options, subcommands, `--`, and usage. Command-specific logic should only validate duplicated specs and enforce value constraints.
- `collection`: structural comparisons of observable attributes.
- `path`: path construction, also used by save commands.
- `vm_service`: RPC error definitions; distinguish connection loss and binding confirmation failure.
- `dart:io` / `dart:convert` / `dart:async`: sockets, OS file locks, UTF-8, `LineSplitter`, JSON, deadlines, queueing.

`marionette_mcp` is pinned to pub **0.6.0** and lockfile is managed accordingly. There is no path dependency on neighboring repositories. Public types and invariants have Dart doc comments.

## Registration

1. Register `CliCommand(ArgParser, decode)` in `CliParser(commands: ...)`.
2. Register the same command name in daemon via `coreCommands()..register(name, handler)`.
3. Add registration to both the product entrypoint CLI and daemon.
4. `decode` converts from `ArgResults` to JSON params. The daemon must also validate params because some clients send directly to IPC.

Common options are parsed by the root `ArgParser` before/after commands, so command-level parsers must not redefine them. Use `addSelectorOptions(parser)` and `parseTarget(args, ref: ...)`. Separate `fill` input text and `swipe` direction in each `decode`. Validate mutual exclusivity of `ref`/`selector` and coordinates, required coordinate pairing, and finite distance before dispatch.

A compiled/registered example is [probe_cli.dart](../integration_test/support/probe_cli.dart). `verify-tap` is a test-only handler used to demonstrate the shared A06 command boundary and is not registered in production B01 tap.

```dart
commands.register('my-action', (context, params) {
  // Validate params, then call the primitive exactly once through the shared path.
  final query = RefQuery(params['ref'] as String);
  return context.performTarget(query, (backend, selector) {
    return backend.tap(ElementTarget(selector));
  });
});
```

## CommandContext responsibilities

| API | Contract |
| --- | --- |
| `snapshot()` | Refreshes the public snapshot and issues monotonically increasing refs for this daemon |
| `performTarget(query, callback)` | Re-observe, check uniqueness and attributes, invalidate all refs, then run `callback` once |
| `performCoordinates(callback)` | Explicit-coordinate flow with validated arguments. Invalidate all refs, then run `callback` once |
| `read(callback)` | Read-only path. Keep refs valid, verify deadline and connection generation around `await` |
| `deadline`, `session` | Absolute deadline and session name. Do not expose auth URI |

The callback must call one backend primitive exactly once. Individual commands must not perform retries, session creation, custom queueing, or mutate snapshot/refs. No UI operations inside `read`. UI action success should return `requiresSnapshot: true`. Verify on-device result via the next snapshot.

`Point` must be finite and non-negative, `ElementSwipe.distance` must be finite and positive, and `CoordinateSwipe` must have distinct endpoints. Build and validate these **before calling** `performCoordinates/performTarget`. Argument errors inside callback may still invalidate refs and be treated as dispatched.

## Backend and observation

`Backend` exposes typed `connect/disconnect/checkConnection/inspect/tap/fill/swipe/captureScreenshots/readLogs`. Images are base64-encoded PNG strings, logs are `LogBatch`. Image decoding, saving, and overwrite prevention for existing files are implemented on B04 CLI side.

The fixed binding 0.6.0 supports `key/text/type`; **`identifier` is not supported**. Use `UNSUPPORTED_CAPABILITY` when requested. Semantics-displayed text is not equivalent to the text matcher, so do not use it for text matching. If possible, use `key` or a unique `type`. Duplicates include hidden observed elements as well. Only captured attributes are exposed.

Re-observation and action dispatch are not atomic. Observation is not a complete tree. There is no guarantee about unobserved elements or changes that happen after re-observation.

## Errors and deadlines

`AgentError` and `Result` provide a unified contract for code, outcome, exit code, and JSON. Do not return or forward raw backend messages, user inputs, or auth URIs. The entrypoint sends `logging` records at INFO or above to stderr, redacts URI values, and omits attached errors and stack traces. Records below INFO remain disabled because upstream extension arguments can contain entered text.

- Invalid arguments: `INVALID_ARGUMENT / not_sent` (never dispatch).
- Stale ref: `STALE_REF / not_sent`.
- Ambiguous match: `AMBIGUOUS_TARGET / not_sent`.
- Queue timeout: `TIMEOUT / not_sent` (do not execute later).
- Post-dispatch disconnect/timeout/indeterminate response: `unknown`. Discard the connection generation and require `connect` and `snapshot`.
- Binding confirmation failure: `BACKEND_ERROR / failed` (ref already invalid).

The daemon re-checks connection generation after `await`, preventing expired operations from overwriting newer observations or connection state. Disconnection is detected through status checks and 1-second queue health probes. Do not depend only on upstream connector `isConnected`.

## Tests and fixture

`FakeBackend` has `elements`, `screenshots`, `logs`, `calls`, and `hooks`. `hooks['tap'] = () => completer.future` reproduces post-send timeout, while `hooks['inspect']` reproduces pre-observation delay. `connected = false` reproduces disconnect. Keep `calls` to action names only so inputs are not logged.

- [binding_0_6_0.json](../test/fixtures/binding_0_6_0.json): synthetic fixture built from fixed `register_extension_internal` and extension response shapes. It is not a full production snapshot.
- [results.json](../test/fixtures/results.json): public envelopes for success, `STALE_REF`, post-dispatch `TIMEOUT`, and empty session list.
- [snapshot_test.dart](../test/snapshot_test.dart): invalidation, attribute changes, different sessions, semantics, duplicates.
- [session_test.dart](../test/session_test.dart): ownership, serialization, timeout, delayed responses, close contention.
- [ipc_test.dart](../test/ipc_test.dart): multi-process, concurrent startup, stale socket, permissions, and compiled binary execution.
- [transport_test.dart](../test/transport_test.dart): protocol mismatch, retry suppression, 64MiB limit.

Run `dart format .`, `dart analyze`, and `dart test` in package. For simulator verification, see [verification record](verification/a01-a06-2026-09-09.md).


## Implemented A07/B01–B05 entry points

The product parser and `coreCommands()` now register tap, fill, swipe, scroll, screenshot and logs. `swipeCommand(coordinates: false)` / `handleSwipe(..., coordinates: false)` implement scroll through the same gesture primitive; its result also identifies `command: scroll`. Tap/fill validate complete IPC arguments before entering CommandContext. Fill stores opaque input under `input`, so `--text` continues to mean a selector.

Screenshot returns internal `images` through IPC; `runCli` then calls `saveScreenshots` to decode base64 and validate PNG with the image package. Only its PNG decoder is imported, avoiding the full codec/filter export graph on every CLI startup. The decoder internal API is isolated in artifact_writer.dart and image is pinned to 4.9.1; PNG contract tests must pass before upgrades. Public success contains only absolute `paths`. Multiple images use `name-1.png`, `name-2.png`; without an extension `.png` is appended for numbered outputs. An omitted path creates a private temporary directory. The writer reserves all output names exclusively and removes only its own files on failure. Missing parent directories are reported as IO_ERROR. It checks the original request deadline during saving; screenshot/logs never invalidate refs.

Logs return `entries` plus nullable `configured`; unknown configuration includes a `limitation`. Binding logs are result data on stdout. Diagnostic logging remains separate on stderr.

Simulator runners: `integration_test/features_smoke.dart` and `integration_test/two_apps_smoke.dart`. See the [B01–B06/A08 verification record](verification/b01-b06-a08-2026-09-09.md) for their environment and results.
