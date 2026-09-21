<a id="marionette_agent--architecture"></a>
<a id="marionette_agent--アーキテクチャ"></a>

# marionette_agent — Architecture

[日本語](ja/ARCHITECTURE.ja.md) · [Documentation index](README.md)

<a id="doctor-boundary-issue-9"></a>
<a id="doctor境界-issue-9"></a>

## Doctor boundary (Issue #9)

`cli/runner.dart` dispatches doctor locally before `RuntimeDirectory.prepare`.
`cli/doctor.dart` owns read-only host/runtime checks, comparisons between fixed dependency declarations and lockfiles, Simulator enumeration, and aggregation of check statuses and exit codes. External processes and probes can be replaced with fixtures.
It connects to a daemon socket only after checking directory ownership and mode 0700, then reads only the handshake through the existing protocol decoder.
It does not call DaemonClient, SessionManager, runtime preparation, or command dispatch.
When a client that only reads the handshake disconnects, DaemonServer reuses the original idle deadline. Only a dispatched request starts a new idle interval, so doctor does not extend the daemon's lifetime.

`backend/doctor_probe.dart` creates an independent client through the public vm_service API and reuses the backend's URI normalization.
It introduces no upstream internal API imports and returns only observed extension registrations and the binding version.
It does not expose the URI or remote error body outside the boundary. A finally block and a late-completion handler release the connection.
Each process/RPC uses the remaining overall deadline; IPC also has a maximum of one second.
Diagnostic results go into the shared Result's data, and the runner uses doctor's data.exitCode as the process exit code.
The text renderer shows check status, reason, next steps, and details; JSON uses the shared envelope.

This document defines the current architecture implementing the `marionette_agent 0.0.1` contract in [SPEC.md](SPEC.md). Standalone commands and workflow v1 are implemented. See the [implementation contract](command-contract.md) for invariants when adding commands.

<a id="system-structure"></a>
<a id="構成"></a>

## System structure

`is visible` uses `SnapshotService.observeTarget` through `CommandContext.observeTarget`, inspecting through the session's read boundary. It shares target re-observation, uniqueness, and stale checks with action resolution; only action resolution rejects invisible targets. The command merely converts nullable visible into known/value. It neither mutates the UI nor updates the public snapshot or refs. Unit and IPC fixtures cover true/false/null and target resolution errors.

```text
AI Agent / Shell
  → Dart CLI (parsing, workflow loading/validation, output, file persistence)
  → Unix domain socket (local IPC for execution requests only)
  → Dart daemon (sessions, serialization, workflows, snapshots/refs)
  → Marionette adapter (VmServiceConnector)
  → Dart VM Service WebSocket
  → marionette_flutter (Flutter app in iOS Simulator)
```

There is one daemon per user and runtime directory. It owns an independent connector and queue for each session. The CLI and daemon are written in Dart. MCP clients invoke the same CLI through a separate, optional stdio MCP process.

<a id="mcp-boundary"></a>
<a id="mcp境界"></a>

### MCP boundary

`cli/commands/mcp.dart` parses startup arguments, and the runner dispatches to `mcp/server.dart` before reading policies or creating the runtime. The `dart_mcp` MCPServer, ToolsSupport, and stdioChannel own JSON-RPC, initialization, version negotiation, and transport shutdown. The server registers fixed profiles, handles pagination and input redaction, converts CLI results into CallToolResult, and turns saved images into ImageContent. No protocol log sink is configured for MCP traffic.

`mcp/catalog.dart` owns typed schemas and the mapping to fixed commands/argv. Options with values use `--name=value`; positional arguments follow `--`, so input strings are not interpreted as CLI options or shell syntax. Arbitrary argv input is not exposed. Domain-specific target resolution and action conditions are delegated to the CLI parser and existing commands.

`mcp/executor.dart` reuses executable-mode detection and launches the same source, snapshot, or compiled CLI once as a normal process. It closes stdin, captures bounded stdout, and drains and discards stderr. It returns the CLI exit code and validated Result envelope to the server. On timeout or MCP shutdown, it cleans up only CLI processes it owns. The existing session layer retains ownership of the daemon and apps, so EOF does not close sessions used by other CLI processes.

Dependencies point from MCP to CLI/IPC. Backend, session, and commands do not depend on the MCP SDK. `test/mcp_test.dart` connects an SDK client, the product stdio process, and a fixture daemon; `integration_test/mcp_smoke.dart` operates the Simulator example through the same route. See the [SPEC contract](SPEC.md#stdio-mcp-server).

<a id="directories"></a>
<a id="ディレクトリ"></a>

### Directories

```text
marionette_agent/
  pubspec.yaml  # CLI package and Pub workspace root
  pubspec.lock  # Shared dependency resolution
  bin/marionette_agent.dart
  skills/       # Hidden stub for external discovery
  skill-data/   # Runtime core/simulator-verify guides and supporting files
  lib/src/
    mcp/        # dart_mcp stdio server, typed tool catalog, CLI process execution
    cli/        # Caller-side parsing, output, file/process handling
      commands/ # Catalog and per-command ArgParser syntax
      command.dart # CliCommand type, independent of the parser
      parser.dart  # Config/environment/CLI precedence and Invocation creation
      help.dart    # Usage text
    diagnostics/# Logging redaction, per-request collection, stderr output
    protocol/   # Versioned requests/responses, errors, DTOs
    daemon/     # Startup, socket server, dispatch, deadlines, serialization
    session/    # Lifecycle and connection ownership
    snapshot/   # Target types in target.dart, refs, target preflight checks
    backend/    # Backend interface and Marionette adapter
    commands/   # Operations using shared services
    workflow/   # Schema, model, parent/step execution control
  samples/workflows/ # JSON/YAML workflows and input samples
  packages/marionette_agent_util/ # Shared host and Flutter helpers
  example/      # Flutter verification app
  test/         # Unit, IPC, and contract tests
    support/    # FakeBackend, input-recording fakes, shared Request fixtures
  integration_test/ # CLI scenarios on Simulator
```

The root CLI, util, and example form one [Pub workspace](https://dart.dev/tools/pub/workspaces). The root lists both members; their pubspecs use `resolution: workspace`. Both the CLI and example declare explicit relative path dependencies on util. Run `flutter pub get` once at the repository root; only the root lockfile and package config are retained. Flutter SDK constraints also apply to the shared test dependencies.

Protocol handles only Dart values and JSON; it does not depend on CLI or args. The commands layer owns IPC parameter validation, typed requests, and handlers. CLI syntax invokes the same validation without introducing a dependency from handlers back to CLI. Internal code imports required definitions directly instead of creating cycles through the public barrel. `architecture_test.dart` rejects dependencies from daemon layers to CLI, args, or the public barrel.

The command layer depends on the Backend interface, never directly on upstream connectors or response maps. URI normalization and redaction live in `backend/connection_uri.dart`, so sessions and state persistence can use them without importing a concrete adapter. FakeBackend lives only in `test/support/` and is not part of the product's public exports. Renderers do not interpret backend exceptions.

Local execution is split across `batch_loader.dart`, `connection_state.dart`, `installer.dart`, and `observation_diff.dart`. `input_file.dart` owns shared regular-file reading, and `process_runner.dart` owns deadline-bound process execution, keeping state, policy, and batch code independent of image-diff and doctor implementations.

<a id="local-boundary-for-skill-distribution"></a>
<a id="skill配信のローカル境界"></a>

## Local boundary for Skill distribution

`cli/commands/skills.dart` owns skills syntax; `cli/help.dart` owns help; `cli/skill_catalog.dart` owns discovery from the package/environment variable, frontmatter parsing, the catalog, and dedicated text/JSON output. The catalog does not depend on the CLI parser. After argument parsing, `cli/runner.dart` executes it and returns before policy loading or RuntimeDirectory.prepare. Success and failure both bypass IPC and do not reference sessions or refs. `--debug` uses existing diagnostics.

CliParser reports the command identified during initial syntax parsing to the caller before loading config. This lets config failures follow command-specific output contracts such as skills. Frontmatter parsing first validates standalone opening and closing lines, reads only that interval, and excludes empty names from the catalog.

The Dart package contains introductory stubs in `skills/` and runtime guides in `skill-data/`. Dart invocation uses Isolate.resolvePackageUri; manually compiled invocation uses a distribution root relative to the executable. `installer.dart` copies both source directories into a new bundle and compiles its relative name as a Dart environment constant. Only a successfully compiled binary replaces the installed one; failure removes the new bundle. Bundles for existing versions remain. There is no runtime extraction, generation, or download path.

The dedicated `SkillsOutput` boundary produces compatibility JSON without changing protocol Result/schemaVersion. See [SPEC](SPEC.md#bundled-skill-distribution) for command details, discovery precedence, and the accompanying distribution bundle contract.

<a id="marionette-adapter"></a>

## Marionette adapter

The adapter reuses VmServiceConnector from `package:marionette_mcp/src/vm_service/vm_service_connector.dart`. Internal API dependencies remain confined to the adapter. The pub dependency `marionette_mcp: 0.6.0` is pinned exactly, and its lockfile is tracked. Contract tests verify response fixtures from the pinned connector and binding.

The neighboring `../marionette_mcp` is reference source and may differ from the resolved pub version. The pinned connector reports success through structured status and provides both swipe modes. It lacks an identifier matcher, which yields UNSUPPORTED_CAPABILITY. Distribution does not require a path dependency on a neighboring repository.

| Local operation | Upstream call |
| --- | --- |
| connect / close | connect / disconnect |
| snapshot | getInteractiveElements |
| tap | tap |
| fill | enterText |
| swipe / initial scroll | swipe |
| screenshot | takeScreenshots |
| screenshot --annotate | callCustomExtension with the fixed name marionette_agent.captureMappedScreenshot (requires an opt-in provider) |
| logs | getLogs |

The adapter handles URI normalization, wire conversion, response validation, and exception classification. HTTP→WS and HTTPS→WSS conversion preserves authentication paths/queries and does not append `/ws` twice. Missing capabilities produce UNSUPPORTED_CAPABILITY. Success is never inferred solely from a message string.

The Backend interface exposes connect, disconnect, inspect, tap, fill, swipe, captureScreenshots, and readLogs with typed arguments and results. Upstream maps stay inside the boundary. Scroll uses the same swipe primitive but retains scroll in help and output.

Annotated capture is a separate MappedScreenshotBackend capability, not a required method on every Backend. MarionetteBackend validates the fixed provider's supported/status, single image, and ScreenshotGeometry v1, then converts the response into a MappedScreenshot DTO. Geometry requires version=1, viewCount=1, a nonempty viewId, originX=originY=rotation=0, positive integer pixelWidth/pixelHeight, and finite positive logicalWidth/logicalHeight. After IPC, the CLI also checks geometry against actual PNG dimensions and applies pixelWidth/logicalWidth on x and pixelHeight/logicalHeight on y. Orientation and scale are not inferred from the image or bounds.

Pinned binding 0.6.0 renders a RenderView layer at FlutterView.physicalSize and, when maxScreenshotSize is set, resizes it to floored dimensions. Failed views are omitted from the image array, so an array index cannot serve as a view ID. ElementInfo.bounds comes from RenderBox.localToGlobal(Offset.zero) and size; normal responses contain no matching metadata. Normal takeScreenshots results are therefore not reused for annotations. In debug mode, example/lib/mapped_screenshot.dart registers an opt-in provider that returns an unresized single-RenderView layer image together with explicit geometry for that view. Changes to view count, identity, physicalSize, or devicePixelRatio during capture are reported as unsupported. No upstream package modification, neighboring-repository path dependency, or overlay injection is required. General binding support would require an equivalent upstream capture-metadata contract; only the example-provider configuration is currently covered by real-environment verification.

SnapshotService.annotationTargets is a read-only path that re-observes and matches published refs. It checks before and after capture without issuing or invalidating refs. CLI screenshot_annotation is a pure PNG-composition boundary that explicitly skips invalid bounds and labels that cannot fit. artifact_writer saves a separate PNG rather than changing the original bytes and checks the same deadline through decoding, composition, encoding, and saving. An arbitrary custom-extension CLI remains out of scope; the fixed provider is the limited exception defined in SPEC.

<a id="ipc-and-daemon-startup"></a>
<a id="ipcとdaemon起動"></a>

## IPC and daemon startup

The CLI sends one request, receives one final response, and exits. IPC uses newline-delimited JSON. Requests contain protocolVersion, requestId, session, command, params, and deadline. Responses contain requestId, redacted diagnostics generated within the request, and the result envelope defined in SPEC. The detached daemon collects `logging` records in a request-specific Zone, then the caller CLI re-emits them to stderr. Records below INFO, authenticated URIs, attached errors, and stack traces are not forwarded. CLI JSON schema and IPC protocol versions are independent.

The runtime directory is private to the user with mode 0700. Socket and startup metadata permissions also prevent access by other users. Paths are kept short enough for macOS socket limits. Startup metadata includes PID, protocolVersion, and a startup identifier; the VM Service URI is not persisted.

An OS exclusive lock serializes startup; after acquiring it, the client rechecks for a running daemon. It starts the same program in internal daemon mode according to whether the CLI is running as Dart source or a compiled executable. It waits for the handshake and reports version mismatches as explanatory errors.

Stale sockets are reclaimed under a lock after liveness checks. A PID alone is never sufficient reason to kill another process. A management queue serializes the final close and new connect. A connection to a stopping daemon can be retried before sending, but a UI operation is never resent after transmission.

The initial IPC limit is 64MiB per frame. Images travel from daemon to CLI as base64; exceeding the limit is an explicit error. The caller CLI saves screenshots and resolves relative paths against its own cwd. Recording is an exception: util saves it within the daemon, and the CLI supplies an absolute path.

`cli/common_options.dart` registers `--screenshot-dir` and rejects empty strings/NUL. `CommonOptions.screenshotDir` reaches `cli/artifact_writer.dart` through the runner; it is not added to IPC params or daemon settings. The writer selects explicit path > directory > temporary storage, leaving directory untouched when a path is supplied. A supplied directory must already exist and be a real directory; it is not created automatically, and a symlink at the directory itself is not followed (ancestor symlinks are allowed). Relative paths are normalized against the caller's cwd, and returned paths are absolute.

Directory mode generates a PNG name directly inside it for each request, including 128 bits of hexadecimal randomness from `Random.secure`. It reuses multiple-image numbering, validation of all images, exclusive reservation of all destinations, writing, and cleanup on failure. A generated-name collision is IO_ERROR like any existing path; it triggers neither overwrite nor recapture. The specified directory is excluded from cleanup. Without it, the unique temporary directory and `screen.png` behavior remains. `screenshot_directory_test.dart` covers collisions and save failures; `screenshot_cli_test.dart` covers product CLI text/JSON, cwd resolution, and configuration isolation between invocations.

Response delivery is bounded by request deadline+250ms, after which sockets of clients that do not receive are disconnected. Following the final close, delivery and disconnection are not awaited indefinitely: remaining clients are discarded after a 250ms grace period, releasing the daemon lifetime lock. Once final-response transmission starts, no second error frame is appended.

<a id="sessions-and-execution-order"></a>
<a id="sessionと実行順序"></a>

## Sessions and execution order

A session moves through connecting→connected→disconnected and is discarded on close. Connection failure disposes the connector. Each session owns its name, normalized URI, connector, connection generation, snapshot, and execution queue. Ref numbering and URI ownership are managed daemon-wide.

Observation, validation, and action within one session share a single queue; different sessions have separate queues. Deadlines are checked on receipt and before execution. An expired request that has not been sent is not executed.

UI actions follow this order: validate arguments/session → resolve and re-observe the target → invalidate refs → send to the backend once → return the result. Successful data includes requiresSnapshot: true.

A connection loss or timeout after sending has outcome: unknown. The connector is discarded and the session becomes disconnected. Timing out a Dart Future does not itself cancel upstream processing, so connection generations are compared to prevent late responses from overwriting newer state.

<a id="snapshots-and-ref-resolution"></a>
<a id="snapshotとref解決"></a>

## Snapshots and ref resolution

The snapshot CLI decoder and command handler share filter validation and pass an optional single selector through CommandContext to SnapshotService. SnapshotService establishes uniqueness and ref numbering across the full observation before filtering returned rows by exact ElementInfo.candidateValue matching. Display text is distinct from trustworthy action matching; identifiers unsupported for actions can still filter observations. Filter metadata (kind/value/matchedCount/totalCount) is established here. retainPublished removes refs outside the filter, and SessionManager's max-output limit may reduce returned refs further. Full counts before omission remain available, and collisions hidden by the filter do not make a target actionable.

Get handlers validate targets at both CLI and IPC boundaries and use SnapshotService's read path through CommandContext. resolveRead shares re-observation, uniqueness, text-origin checks, and ref attribute comparisons; action resolution additionally checks visible. Neither issues refs, and get never invokes mutation. Count bypasses the uniqueness-requiring resolver and, after capability checks, counts exact candidateValue matches in inspect results. Text from unknown types counts as a candidate without being treated as actionable. The handler's result schema explicitly represents missing attributes as null and bounds in Flutter logical pixels.

SnapshotService normalizes element information. RefStore maps each ref to an observation generation, selector, and element attributes. It selects a unique candidate in key, identifier, verified text, then type order. Public snapshots are separate from internal preflight observations so preflight validation cannot issue new refs.

Public snapshot generation is linear: it first counts matches per selector, then checks deadline and connection generation and yields to the event loop every 256 elements. Text matching for the pinned binding is limited to five known types. Unknown types cannot be distinguished from Semantics-derived types, so their text is display-only and actions use key/type. Invalid observation objects become BACKEND_ERROR within the adapter.

ElementInfo.value returns a trusted selector candidate; candidateValue returns an observed value that may collide. Text duplicate counting, re-observation, and wait use candidateValue so unknown types also count. A sole text candidate of unverified origin produces UNRESOLVABLE_TARGET.

Here, `ElementInfo.value` retrieves a selector candidate, not an input-value read API. The [future design for Issue #14](semantics-selector-state-design.md) separates display, matching evidence, and typed values/state. Raw diagnostic attributes from the pinned binding may be stringified or omitted, so they do not justify exposing typed state through the adapter. Semantics hierarchy, IDs linking Widgets to Semantics, attribute provenance, and per-action capabilities remain upstream dependencies. That design does not add them to the current DTO/CLI.

Marionette's element list is not a complete tree, and Semantics display text may not match TextMatcher. Array indices are not selectors. If a target cannot be established, return readable information and a reason. Upstream selects the first match, so contract tests include duplicates, Semantics wrappers, and hidden elements.

Preflight observation does not guarantee atomic target selection; the limitations in SPEC apply. The initial release does not add persistent app-side element IDs.

<a id="ownership-of-shared-contracts-ssotsolid-review"></a>
<a id="共通契約の所有ssotsolidレビュー"></a>

## Ownership of shared contracts (SSOT/SOLID review)

`usesSession` in `protocol/command_scope.dart` is the source of truth for whether a result has a session. Normal CLI parsing, syntax-error recovery, Invocation, IPC Request/client/server, and SessionManager all use it. Even argument errors for `close --all` have session: null, and a string passed as an option value is never reinterpreted as a flag. IPC workflows are execution requests only, so Request evaluates them as action=run.

`commands/*_request.dart` contains side-effect-free input definitions and validation; handlers perform observation and actions. `wait_request.dart` separates duration waits and target waits into distinct types and shares ref/selector exclusivity, state, and polling interval between CLI and daemon. The workflow schema's state and polling range are built from these definitions. This does not add refs or duration waits to workflow v1.

`SessionActionPolicy` privately owns the policy and pending approvals. Its authorize method receives only a Request and connection generation, with no dependency on Session, CommandContext, or handlers. Find, batch, and workflow use input definitions to inspect nested actions; find interprets its action after validation. Session only requests approval invalidation on disconnect. `architecture_test.dart` rejects reintroduction of transitive dependencies from policy to the session execution layer.

Single-session and all-session close share URI ownership release, ref invalidation, disconnection waiting, and failure classification in `SessionManager._disconnectSession`. Session retains the latest disconnect Future and returns its result to a later close even if app-exit notification or timeout discarded the session first. It neither sends disconnect twice nor reports unconfirmed disconnection as success. Recording finalization and owned-app shutdown remain with their existing owners.

<a id="command-extension-boundaries"></a>
<a id="コマンド拡張境界"></a>

## Command extension boundaries

`find` passes the ElementInfo selected by display conditions to `SnapshotService.uniqueTarget`. Matcher candidates are selected in key/identifier/text/type order from one re-observation. `ObservedQuery` stores the selector and attributes observed at selection. Immediately before the action, normal resolution compares those attributes too; replacement under the same key produces STALE_REF / not_sent. ObservedQuery exists only within a request and is accepted neither as IPC input nor as a public ref.

`drag` calls `SnapshotService.resolveAll` through `CommandContext.performTargets`, checking both targets' refs, attributes, uniqueness, and visibility against the same inspect result. Only after all checks pass does the shared mutation path invalidate refs and send once. Target validation failure leaves refs intact and sends no action. This does not guarantee atomicity between re-observation and the app action itself.

`batch_loader` parses only each argv's syntax, duplicate options, and command params. It does not re-resolve the parent's common options or revalidate environment session/timeout values already overridden by the parent. Snapshot diff hashes structurally equivalent rows and compares counts while preserving duplicates. It avoids quadratic pairwise scanning and checks the same deadline within loops.

Normal app commands register the same name with the CLI parser and daemon CommandRegistry. Record branches to RecordService through SessionManager's shared session queue. Only platform=flutter receives the connected backend and URI; other recording modes are independent of VM Service. Handlers do not trust IPC params: before mutation, they revalidate unknown fields, types, required fields, and exclusivity. Shared ref/selector and finite-number validation lives in `commands/arguments.dart`.

CommandContext centralizes session execution, target resolution, deadline checks, ref invalidation, and a single mutation send. Handlers do not implement their own queues, retries, session creation, ref storage, or connection disposal. Types for external CLI composition are exported through `lib/marionette_agent.dart`; internal handlers import required files directly. Upstream connectors and response maps never leak into the command layer.

SessionManager branches workflows away from the normal route, but each step uses the existing CommandRegistry and a new Execution/CommandContext. A single Execution never sends multiple mutations, and steps never recursively invoke SessionManager.

Standalone and workflow waits normalize to the same CommandRegistry handler. It revalidates selector, state, and polling interval, then serially polls only inspect through CommandContext.read. It creates no public snapshot or refs and has no mutation path or automatic retry. Workflow sets a step-specific deadline on the child Execution before invoking the same handler.

<a id="verification"></a>
<a id="検証"></a>

## Verification

- Unit tests: argument exclusivity and finite values, JSON and exit codes, ref invalidation, ambiguity, session isolation, and workflow parsing/binding/execution.
- Adapter contracts: mappings and failures using pinned-dependency response fixtures and FakeBackend.
- IPC: state persistence between CLI processes, simultaneous startup, concurrent sessions, close races, daemon shutdown, shared wait deadlines, and timeouts before/after sending.
- Simulator: use `example/` to verify two independent apps, input fields, PageView, Dismissible, scrolling regions, logs, standalone wait for appearance/disappearance, workflow stopping, and final snapshots.

Passing FakeBackend tests does not replace Simulator verification. Code changes require format, analyze, and relevant tests in the package, plus the full suite at handoff. Simulator records include Flutter/binding versions, Simulator model/OS, commands, and observations.

<a id="existing-implementation-facilities"></a>
<a id="実装で利用する既存機能"></a>

## Existing implementation facilities

Use args for argument parsing/usage, collection for attribute comparison, path for paths, image for PNG decode validation and JPEG conversion, and vm_service for RPC error definitions. IPC uses dart:io Unix sockets and OS file locks, plus dart:convert UTF-8/LineSplitter/JSON. Custom logic is limited to product-specific requirements such as session lifetime, ref validation, deadline/send-outcome contracts, and frame limits.

The upstream connector's isConnected alone cannot detect communication loss. Status queries and one-second health probes therefore run on the session queue. After the CLI request deadline, IPC gets up to 250ms to deliver the daemon's TIMEOUT response; this does not extend backend execution.

<a id="workflow-v1"></a>

## Workflow v1

Following the [workflow specification](workflow-file-spec.md), the CLI WorkflowLoader reads JSON/YAML within a deadline and validates all steps and input bindings through a closed bundled schema and WorkflowPlan. `yaml 3.1.4` is pinned exactly; dependence on its internal scanner is isolated to the loader. Tags, anchors, aliases, and excessive depth are rejected at token level; a structural scan detects duplicate JSON keys. The schema is bundled as Dart constants, so compiled CLI use needs no external file or network. `workflow schema` and `workflow validate` create neither RuntimeDirectory nor daemon.

SessionManager branches workflows outside standalone Execution.bound. WorkflowExecution owns one queue entry, starting epoch, overall deadline, stop state, progress, and snapshot candidate. Each step receives a new Execution bound to the parent, preserving the existing single-send guard. The parent does not reclassify outcomes established by a step. On timeout, it stops and discards only the starting epoch. Late Futures check the parent's stop state, so they cannot change new connections, refs, or later steps.

Wait steps use the same registered read handler as standalone wait, polling inspect with ElementInfo.candidateValue matches and checking provenance for a sole text candidate. CommandContext.check also validates the deadline after computation. No public refs are created. Every step invokes CommandRegistry directly without per-step recursion into SessionManager. Later mutations discard the final-snapshot candidate, and failure never returns it.

IPC protocolVersion 7 adds managed-app startup/shutdown (6 added session action policy; 5 added per-request debug policy; 4 added shared output policy and the idle-configuration handshake). Workflow request params contain only the workflow template and inputs object. The daemon validates the entire request before checking connection and selector capabilities. AgentError.details survives IPC and withOutcome. Delivery failure produces unknown/progressKnown:false and never resends UI actions. Schema/validate do not call RuntimeDirectory.prepare.

Even daemon fallback responses preserve unknown/progressKnown:false and the session name when workflow response-frame generation or delivery fails. CLI local validation checks the absolute deadline after parsing and semantic validation, never returning a late success.

<a id="cli-side-screenshot-conversion-issue-13"></a>
<a id="screenshotのcli側変換issue-13"></a>

## CLI-side screenshot conversion (Issue #13)

`cli/common_options.dart` owns root registration of format/quality, PNG and JPEG quality 90 defaults, value validation, and extension rules. `CliParser` validates screenshot paths before connecting and appends the selected format's extension when absent. Help/version and all subcommands inherit the same definitions. Format/quality pass from Invocation's CommonOptions to the runner, not IPC params or the backend adapter. This adds neither workflow screenshot support nor a protocolVersion change.

`cli/artifact_writer.dart` decodes and validates every backend PNG. If annotations are requested, it first composites them into PNG using the supplied geometry, then proceeds to output-format handling. Unannotated PNG keeps its original bytes. JPEG uses 8-bit RGB composited over white and the pinned image 4.9.1 JpegEncoder. RGBA, grayscale alpha, palette, and 16-bit images use normalized pixel values, compositing before alpha is discarded. Since the encoder is not responsible for alpha composition, repeated composition caused by JPEG edge padding is avoided. Quality 0 is clamped to the encoder's minimum of 1. Internal image imports remain at the same boundary as the existing PNG decoder; dependency updates require rechecking image fixtures.

The runner passes the original common absolute deadline from CLI startup unchanged to the writer. It checks after decoding, composition, and encoding, then proceeds to the existing exclusive reservation and writing of all destinations. Synchronous codecs are not interrupted, but late images are never published as success. Failure/TIMEOUT after reservation cleans up this request's reserved/written files and automatic directory. OS cleanup failures may leave artifacts, but no successful paths are returned and the original error is preserved. An injected clock tests expiration after conversion, reservation, and writing independently of host load.

<a id="inputoutput-safety-boundaries"></a>
<a id="入出力の安全境界"></a>

## Input/output safety boundaries

- Image persistence reserves every destination through Dart exclusive file creation before writing. Existing files, directories, and symlinks are never overwritten; partial failure removes files created by this request. Deliberate replacement of a destination by another process after reservation is outside the guarantee.
- Workflow path inputs must be regular files. FIFOs and similar inputs fail argument validation before opening. Streaming input uses deadline-bound stdin (`-`).
- The diagnostics Zone contains a closable collector that drops its List reference when the request completes. Later logs from listeners registered during connection return to the normal stderr path.

CommonOptions owns `--debug` and its recovery during syntax errors. Request.debug is a bool, default false, rather than a daemon-wide setting. DebugDiagnostics adds only fixed-enum stages, restricted request ID/session, Stopwatch elapsedMs, and allowed normalized codes to the existing logging route. It exposes CLI parsing/runtime/IPC startup/send and daemon dispatch/queue/execute/result. Daemon events are collected in the existing request Zone, placed in response diagnostics, and re-emitted to the caller's stderr. Normal diagnostics and public JSON schemaVersion=1 stay unchanged. Elapsed times start independently for CLI, IPC, daemon dispatch, and session queue intervals; differences across intervals do not represent duration. The final CLI result represents overall success or failure.

- Ref/selector exclusivity, types, empty strings, and finite-number checks are centralized in `commands/arguments.dart` and shared by the CLI target parser and daemon action handlers.
- Text output shows outcome for every error, including normal commands. Workflow errors also include whether progress is known, completed step count, and the failed step. The daemon classifies response-generation failures after request processing starts as unknown.

<a id="internal-platform-services"></a>
<a id="内部プラットフォームサービス"></a>

## Internal platform services

`packages/marionette_agent_util` is an internal package for OS/device-specific operations needed by marionette_agent and Flutter app-side debug helpers, not just recording. It has no reverse dependency on CLI/session/protocol or marionette_mcp. Future device-information functionality also belongs in independent services.

```text
CLI parser → RecordService (shared argument validation and error conversion)
            → RecordingManager (ownership, device exclusion, storage, shutdown)
              → ScreenRecorder / RecordingHandle
                → iOS: simctl / Android: adb / macOS: screencapture
                → Web: Chrome CDP lifecycle + macOS screencapture
                → Flutter: FlutterScreenRecorder → PngScreenRecorder + ffmpeg
```

`marionette_agent_util.dart` exports host-side Dart APIs; `flutter.dart` exports app-side Flutter APIs. They do not export each other. CLI execution and compilation require no Flutter engine, but both CLI and util use `flutter pub get` to resolve Flutter SDK dependencies. Host tests live in `test/`; Flutter tests live in `flutter_test/`.

The CLI has a path dependency on `../marionette_agent_util` within the same repository. Both packages use publish_to:none. Distribution runs from a checkout containing both packages or uses a compiled CLI binary. No path dependency on neighboring reference repositories is introduced.

Record start, connect, and launch can automatically start the daemon. A session can be reserved and retained solely for recording, with VM Service connected later. Record start/stop/status and close are serialized on the existing session queue; long-running frame processing continues outside it. Recording does not use the UI-mutation Execution.bound: util manages startup deadlines, bounded cleanup after stopping, and state. Discarding a VM Service epoch does not affect the recording handle. Failure to acquire the Flutter recording connection marks that recording as failed.

RecordingManager reserves the device before starting and returns after backend startup confirmation. Waiting for the backend is bounded by the request deadline and a 30-second maximum. Stopping late-created handles and reclaiming reservations continue as tracked cleanup. Even a shutdown race during start or a stop failure retains the device reservation until handle termination is confirmed. Finalization continues after a stop request times out, and no new recording may use the device until it finishes. Android automatic completion joins the same finalization path. Close finalizes recording before releasing ownership. On daemon SIGINT/SIGTERM, RecordingManager.dispose bounds pending starts, stops, saves, and tracked cleanup to 60 seconds. On expiration, RecordingHandle.abort force-stops owned processes, cancels file reads, and closes output, with at most five more seconds of waiting. Staging and unfinalized reserved destinations remain, and late completion cannot publish a video. Android attempts forced stop after matching a unique remote path and PID, but success is not guaranteed for a disconnected device. In-flight OS I/O cannot be guaranteed cancellable, so deletion is not raced against it.

Destination reservation, private staging, iOS SIGINT, Android's unique remote filenames and SIGINT to a PID verified by cmdline, adb pull, and macOS startup-liveness checks/shutdown remain inside util. Child-process output is never forwarded to CLI stdout. PlatformException becomes AgentError. Unsupported linux/windows are also rejected in util and validated through shared checks in both CLI parser and daemon.

Unit tests cover save protection, device exclusion, startup failure, stop deadlines, abnormal exit, and shutdown races. CLI tests cover disconnected recording sessions, ref retention, continuation after connection loss, close, and unsupported platforms. `integration_test/record_smoke.dart` uses the product CLI to verify start → connect → action → video finalization → duplicate stop → overwrite rejection → close finalization. It decodes the actual video and checks screen changes.

<a id="recording-rendered-output-from-hidden-apps-issue-20"></a>
<a id="非表示アプリの描画録画issue-20"></a>

### Recording rendered output from hidden apps (Issue #20)

`ScreenshotConnectionBackend` is an optional backend capability exposing only creation of a recording-specific `ScreenshotConnection`. `MarionetteBackend` opens a separate upstream connector instance with capture and disconnect. This connection neither discovers the interaction provider nor calls keyboard.release on disconnect. It is independent of the action session's connection, epoch, and refs.

`FlutterScreenRecorder` adapts connection ownership, startup deadlines, and base64 conversion. Upstream internal imports remain confined to `marionette_backend.dart`. Util's `PngScreenRecorder` depends only on capture/close callbacks and owns PNG dimension validation, sequential file persistence, monotonic capture timestamps, and VFR conversion with ffconcat. A ScreenRecorder is injected into RecordingManager per recording, sharing existing save protection, stop, close, and late cleanup. Individual capture and feed shutdown each have a five-second limit; ffmpeg conversion has 30 seconds. Capture errors never become successful videos; recovery staging may retain PNGs and a partially generated video.

The macOS fixture's MainFlutterWindow suppresses NSWindow display through an explicit environment variable and starts a FlutterEngine. Flutter's debug-only `enableHeadlessRendering()` preserves hidden/paused/detached notifications while keeping frames running through scheduleForcedFrame every 16ms. Returning to visibility or disposing stops the timer. Other apps must implement hiding of their own native window. Normal startup without opt-in follows the existing lifecycle. iOS, Android, and Web use their standard headless startup mechanisms, not platform emulation through tester.

For platform=flutter, `record_smoke.dart` connects or launches first, then verifies actions, saved recordings, duplicate stop, existing-output protection, and save-on-close across all five environments, including tester. PNG recorder unit tests cover capture failure, dimension changes, mid-run abort, conversion failure, and actual capture intervals. Widget tests verify rendering opt-in and its removal.

<a id="common-options-issues-2-and-8"></a>
<a id="共通オプションissue-28"></a>

## Common options (Issues #2 and #8)

`cli/common_options.dart` owns common-option names, help, CLI defaults, ArgParser registration, duplicate detection, syntax-error recovery, option-specific validation, and CommonOptions. CliParser registers them once at root; args inheritance applies them to every command/subcommand. Individual command parsers do not copy definitions. Shared range checks for session names, durations, and output limits live in protocol and are called by both CLI and IPC.

CliParser passes the caller's Platform.environment (an injected map in tests) to CommonOptions.createParser. ArgParser defaults for session/timeout use environment > built-in default, and args prioritizes explicit CLI values. Validation runs only after selection; an empty value is not treated as unset. Syntax-error recovery uses the same parser's session default instead of duplicating environment resolution. The runner uses the existing path to convert the selected timeout into an absolute deadline measured from before parsing. The daemon and session queues never re-resolve environment variables.

Request carries `maxOutput` and `outputJson` outside params. Daemon limiting and CLI rendering share the item serializer in `output/content.dart`, so their code-point budgets agree. SessionManager applies limits after completing the public snapshot inside the queue. SnapshotService.retainPublished removes omitted refs from the returned generation before releasing the queue. Workflow finalSnapshot follows the same path, leaving no interval in which later requests can use unpublished refs. Only the renderer generates a nonce per CLI invocation; JSON adds it as metadata on the relevant data.

DaemonClient passes the startup idle value through internal daemon arguments. Idle defaults and range validation share protocol definitions; only internal daemon CLI parsing uses CommonOptions. Handshake and private metadata contain the resolved idleTimeoutMs. The client rejects a mismatch with an explicit value before sending a request, including when reopening after acquiring the startup lock. Omitting the option never overwrites an existing value, and the daemon is not restarted solely to change it.

DaemonServer watches client receive/delivery and SessionManager pending work, starting the idle timer only once all queues are empty. Expired entries remain pending until actually drained. Queue-completion notifications restore a missing timer after health probes but do not extend an existing idle interval. Expiration during a health probe waits for its completion. The timer joins normal close, sharing recording finalization, all-session disposal, socket deletion, and lifetime-lock release.

<a id="closing-all-sessions-issue-6"></a>
<a id="全session終了issue-6"></a>

## Closing all sessions (Issue #6)

The CLI parser converts close --all into params:{all:true} and rejects combining it with explicit common --session. With no daemon, DaemonClient returns session:null and an empty sessions array. SessionManager uses synchronous reservation on receipt and existing session queues as its management serialization boundary, sets stopping, and fixes the target set. Pre-execution checks reject queued requests with not_sent. A barrier on existing queues waits for running work until the shared deadline, then recording finalization and disconnection are aggregated concurrently across sessions.

Session.interrupt wakes only the current Execution; Execution.bound chooses unknown/not_sent from its own sent state. Its listener is removed on completion. Generation invalidation stays in the existing discard path, whose Future only global close awaits with a deadline to observe disconnection failures. Workflows use the same bound on each child and preserve progress. Aggregate-result delivery joins DaemonServer's existing onEmpty, shutdown, socket deletion, and lifetime-lock release, retaining bounded disposal of nonreceiving clients. SPEC's close --all section owns the public result and race contracts.

<a id="web-display-recording-issue-16"></a>
<a id="webディスプレイ録画issue-16"></a>

## Web display recording (Issue #16)

`web_target.dart` defines the closed syntax `display:<index>@<local page endpoint>`. RecordingTarget maps Web keys to `macos:<display>` too, letting RecordingManager's synchronous reservations enforce physical-target exclusion between Web recordings and macos. RecordingTarget owns the extension, keeping validation and staging names aligned: MOV for Web/macOS and MP4 for iOS/Android.

`WebScreenRecorder` uses a dedicated HttpClient without a proxy to connect to the explicit loopback page and check Browser.getVersion, Target.getTargetInfo, and Inspector.enable within the deadline. Raw CDP errors are converted to allowed explanations, not exposed. Late WebSocket upgrades are closed. The Chrome connection is monitoring-only, never used for page actions, image transfer, or VM Service.

After validating Chrome, it passes the explicit display to the same PlatformScreenRecorder macos backend. The wrapper handle treats tab closure, crash, or connection loss as failure and joins native stop. If disconnection happens during startup, it also stops the native handle returned later. It retains native isRunning/ended so the display reservation stays held until termination is confirmed. Normal stop/abort closes only its own CDP connection, never Chrome or other tabs. The CLI retains its existing RecordService, session queue, and shared error conversion.

At Web startup, CoreGraphics `CGPreflightScreenCaptureAccess` is read through Dart FFI. Missing permission produces IO_ERROR before Chrome connection or native recording. Permission-request APIs are never called. Environments without that API produce UNSUPPORTED_CAPABILITY.

<a id="additional-flutter-features"></a>
<a id="flutter向け追加機能"></a>

## Additional Flutter features

The [Flutter extensions in SPEC](SPEC.md#flutter-extensions) and [additional command specification](cli-parity.md) are the sources of truth.

- `marionette_agent_util/flutter.dart` exposes optional debug-only providers. It reads attributes through public Widget/State APIs, separates controller values from display text, and never transmits password values. Mounted-Widget observation, target re-matching, and a finite interaction set stay within fixed-name extensions. No complete Semantics tree or persistent IDs are introduced.
- Only `MarionetteBackend` detects provider registration, checks versions, converts DTOs, and uses pinned-binding APIs. Without registration, it uses stock observations. `InteractionBackend` and `ClipboardBackend` are optional capabilities that never expose upstream maps to normal commands.
- Snapshot filtering happens after collision checks and numbering across the full observation but before ref retention is finalized. Positional find selection also becomes a unique existing matcher and goes through the shared action path. Crop uses target checks before/after capture and explicit geometry, sharing the artifact writer's exclusive persistence. Diff reads a baseline on the CLI side and compares it with an image or nonpublic read observation. Clipboard write/copy tracks the send outcome through an effect path that does not invalidate UI refs.
- Batch occupies one session queue entry. Each step has a separate Execution, preserving the single-send guard. It stops at the first failure and returns progress. Workflow v1 syntax is unchanged.
- Action policy is checked inside the session queue before execution, including actions nested in find/batch/workflow. Pending requests are bound to a session connection generation and expiry. Approval consumes a request once and then uses normal target resolution. Close/disconnect discards pending requests. Policy is an opt-in feature modifiable by the same user, not an IPC authorization boundary.
- Config, connection state, diff, and install/upgrade are CLI-side file operations. Authenticated URIs in connection state pass through private IPC into newly created mode-0600 files, never public responses. Namespace separates runtime names. Doctor is normally read-only; only fix repairs the mode of a runtime directory owned by the user.
- `marionette_agent_util` owns device-enumeration and FPS-conversion processes. FPS conversion happens after recording finalization in private staging and does not guarantee native capture frequency. Restart performs stop→start in the same recording queue, finalizing the old video. Failure to start the new recording never resumes the old one.

<a id="ownership-of-hybrid-execution-environments"></a>
<a id="ハイブリッド実行環境の所有権"></a>

## Ownership of hybrid execution environments

The CLI catalog's launch validates arguments through util LaunchOptions before passing them to IPC. SessionManager synchronously reserves the session, applies policy, then calls ApplicationLauncher.start. It retains the owned RunningApplication returned by util and reports launch success only after connection and the first inspect succeed. Connection reuses existing _connect rather than duplicating URI ownership, connection-generation, or ref rules. Normal connect does not acquire app ownership.

marionette_agent_util/src/application provides LaunchOptions, PlatformApplicationLauncher, RunningApplication, and OwnedProcess. Platform-specific Flutter/simctl/emulator/adb arguments, SDK discovery, private temporary storage, project exclusion, URI discovery, and execution shutdown stay inside util. Util does not depend on CLI, IPC, or the Marionette backend. The agent's backend adapter handles Marionette connection and observation. The NSWindow/rendering support inside macOS apps is app-side opt-in; the Dart CLI never creates a native view.

OwnedProcess starts with an argument array, retains bounded stdout, and interprets Flutter machine app.start. Web waits for the corresponding app.started as well as URI output to avoid connecting before Flutter initialization. Raw logs are not forwarded to stderr. It requests normal exit with app.stop and signals only owned processes on timeout, never killing processes by name. iOS creates, shuts down, and deletes a private device set. Android owns only the new read-only Emulator and never stops the shared adb server. The owner also cleans up disposal during startup and late Process.start completion.

Close finalizes through the existing RecordingManager, calls RunningApplication.stop, then discards the session. An app-exit notification invalidates the generation only if that handle still belongs to the same session. Close --all and daemon disposal use the same util shutdown. CLI tests cover launch, connection-readiness failure, policy, nonownership of external connections, and abnormal exit. Util tests use real fixture processes for startup, timeout, interruption, project exclusion, and shutdown.
