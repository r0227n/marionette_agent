<a id="marionette_agent--product-specification"></a>
<a id="marionette_agent--製品仕様"></a>

# marionette_agent — Product specification

[日本語](ja/SPEC.ja.md) · [Documentation index](README.md)

<a id="environment-diagnostics-doctor-issue-9"></a>
<a id="環境診断-doctor-issue-9"></a>

## Environment diagnostics: doctor (Issue #9)

`doctor [--probe-uri <uri>]` runs local diagnostics without an app connection. Its session is null.
Normal execution does not create a runtime, change permissions, delete sockets, start/stop a daemon, install packages, or boot a Simulator. Additional `--quick/--offline/--fix` modes follow the Flutter extensions below.
It sends no requests to existing sessions, backends, or refs. For a daemon, it reads only the handshake and closes the connection.
A handshake-only query does not reset the daemon's existing idle deadline.

A completed diagnostic run has an `ok:true` envelope and data containing `doctor:true`, `exitCode`, and `checks`.
Each check has `id`, `status`, `reason`, a user-executable `nextStep`, and `details`.
Status is `success` (condition verified), `failure` (noncompliance verified), `unknown` (timeout/observation failure), or `skipped` (target absent/no explicit probe/prerequisite unmet).
Any failure or unknown yields exit 1; otherwise exit 0. This aggregation is specific to diagnostics; argument errors and similar failures use the normal error contract.
`--timeout` bounds the entire run, including every check. Expired and remaining checks become unknown, yielding exit 1.

Check IDs and targets:

- `host.os`: macOS. `host.dart`: the executing SDK is >=3.13.2 <4.0.0.
- `runtime.socketPath`: the same absolute path and 80 UTF-8 byte limit as the existing runtime; measures bytes including socket `/s`.
- `runtime.directory`: no symlink, owned by the current user, mode 0700. Absence is skipped without creating it.
- `daemon.ipc`: passively connects to a socket in a verified-safe directory and checks protocolVersion compatibility and ready state. Absence is skipped; rejection/mismatch is failure; no response is unknown. Limit: one second or the remaining deadline, whichever is shorter.
- `dependencies.fixed`: compares pinned marionette_mcp, image, and yaml versions in the CLI package's pubspec/lock. Missing or unreadable files are unknown. This does not guarantee the version of the actual binding or installed artifacts.
- `simulators.ios`: observes iOS device name/UDID/runtime/state through `xcrun simctl list devices available --json`. Zero devices is failure; query failure is unknown. It neither boots nor repairs devices.
- `probe.vmService`: creates an independent VM client only when `--probe-uri` is supplied, querying getVersion/getVM/getIsolate and only the registered `ext.flutter.marionette.getVersion` extension. Omission is skipped; connection/RPC errors are failure; timeout is unknown. The binding version is reported only from a valid response; capabilities include only actually registered extension names. Unobserved versions are null/unknown and an unobserved binding is unknown. Registration does not guarantee action success.

Authenticated probe URIs, remote exceptions, and input strings are excluded from results and diagnostics. The independent connection is released on completion, failure, or timeout; connections established late are also closed. External query processes are terminated on timeout.

Status: the implemented `marionette_agent 0.0.1` contract, including standalone commands and workflow v1. See the [English site](https://r0227n.github.io/marionette_agent/en/) for usage, [supplements](cli-reference.md) for detailed execution rules, and [architecture](ARCHITECTURE.md) for internal implementation boundaries.

<a id="purpose-and-scope"></a>
<a id="目的と対象"></a>

## Purpose and scope

Enable AI agents to observe and operate Marionette-enabled Flutter apps through a Dart CLI. The interaction model adopts agent-browser's sessions, snapshots, short element references, and structured output. Browser-specific command compatibility is not a goal.

The initial host is macOS, and the primary UI target is an already-running Flutter app in iOS Simulator. Recording separately supports iOS Simulator, Android, and macOS displays, including Chrome Web verification. Apps must run in debug mode with the `marionette_flutter` binding initialized and an accessible VM Service URI. In addition to connect for manually started apps, launch can explicitly select and start headless tester/iOS/Android/macOS/Web environments.

A stdio MCP server exposes the existing CLI interaction model to MCP clients. It uses the Dart connection implementation from `marionette_mcp` as a library to invoke Flutter extensions through VM Service. Providing an MCP client product or HTTP transport is out of scope.

<a id="terminology"></a>
<a id="用語"></a>

## Terminology

| Term | Meaning |
| --- | --- |
| session | A named unit holding the connection and observation state for one Flutter app |
| daemon | A resident local process that preserves session connections and references between commands |
| snapshot | An observation of actionable elements and readable information from Marionette, not a complete Widget tree |
| ref | A short reference such as `@e1` selecting an element from a snapshot |
| selector | An explicit target selected by one of key, identifier, text, or type |

<a id="cli-contract"></a>
<a id="cli契約"></a>

## CLI contract

The executable is `marionette-agent`; the Dart package is `marionette_agent`. It is registered as an executable in `pubspec.yaml`.

```sh
marionette-agent --session demo connect 'ws://127.0.0.1:12345/token/ws'
marionette-agent --session demo snapshot
marionette-agent --session demo tap @e1
marionette-agent --session demo snapshot
marionette-agent --session demo fill @e5 'hello'
marionette-agent --session demo snapshot
marionette-agent --session demo swipe @e9 left --distance 200
marionette-agent --session demo screenshot ./screen.png
marionette-agent --session demo close
```

Refs here are examples. Use refs returned by the latest snapshot during actual execution.

<a id="common-options"></a>
<a id="共通オプション"></a>

### Common options

| Option | Contract |
| --- | --- |
| `--session <name>` | Defaults to `MARIONETTE_AGENT_SESSION`, or `default` if unset. Up to 64 alphanumeric, `_`, or `-` characters, starting with an alphanumeric character |
| `--json` | Writes one JSON object to stdout |
| `--timeout <ms>` | A positive integer representable by Duration and DateTime. Defaults to `MARIONETTE_AGENT_TIMEOUT_MS`, or 30,000ms if unset. Includes queueing, connection, and processing. Out-of-range values are INVALID_ARGUMENT |
| `--debug` | Valueless flag, disabled by default. Writes request ID, session, processing stage, elapsed ms, and final normalized error code to stderr |
| `--content-boundaries` | Valueless flag, disabled by default. Identifies snapshot elements/log entries as untrusted content |
| `--max-output <chars>` | Positive integer, unlimited by default. Limits snapshot/log item sequences in Unicode code points |
| `--idle-timeout <duration>` | Daemon-wide idle deadline. Default 1h; 0 disables it. Integer ms or an ms/s/m/h suffix |
| `--screenshot-format png\|jpeg` | Screenshot output format, default png. Backend remains PNG; the CLI converts to JPEG |
| `--screenshot-quality <0-100>` | Integer accepted only with JPEG selected, default 90. PNG, quality alone, and out-of-range values are INVALID_ARGUMENT |
| `--screenshot-dir <path>` | Existing directory for screenshots without an explicit path. Unset by default. Explicit path wins; omitting both uses the existing temporary-storage behavior |
| `--help` / `--version` | Available without a connection |

Common options are accepted before or after subcommands. Repeating an option is an argument error. Normal operation does not prompt; only explicit `--confirm-interactive` asks for confirmation on a TTY. Normal output is concise text; diagnostics go to stderr. Missing arguments cause a nonzero exit and show available syntax.

Session and timeout each resolve as explicit CLI > environment > explicit config > default. Existing name, positive-integer, and Duration/DateTime range validation applies only to the selected value. An empty environment value is set, not absent, and invalid values yield INVALID_ARGUMENT. Environment values overridden by explicit CLI are not validated, even if empty or invalid. Missing, duplicate, or invalid explicit CLI values are errors rather than a reason to fall back to the environment. Environment variables resolve per CLI invocation; the selected timeout becomes the existing absolute deadline, including queue waiting. Config is supplied through explicit `--config`. No environment fallback is provided for credentials, session id, or idle-timeout.

Even syntax errors reflect a valid selected session, including environment-derived values, and JSON mode. `close --all` uses session:null even for argument errors. An invalid session or a session-independent command also uses null. Option values and strings after `--` are not interpreted as common options.

`--debug` adds opt-in diagnostics, including for syntax errors, while preserving normal diagnostics and the existing stdout envelope. It travels from CLI to daemon per request and is not shared between concurrent sessions. Stages include CLI parsing, runtime preparation, daemon connection/startup/ready, send, dispatch, session queue, command execution, and result. Each process reports monotonic elapsed ms from the start of its own processing interval; results include `OK` on success or a normalized error code. Detailed diagnostics exclude authenticated URIs, fill inputs, selector values, app display text, error message/details, and stack traces.

<a id="common-safety-options"></a>
<a id="共通安全オプション"></a>

### Common safety options

`cli/common_options.dart` is the source of truth for registration, CLI defaults, precedence, and output-mode recovery on syntax errors; every subcommand inherits the same root definitions. `protocol/protocol.dart` defines session-name, deadline, and output-limit ranges and the daemon idle default, shared by CLI and IPC. Common options, including `--debug`, are accepted for help/version, workflow, and record. Duplicates, missing values, and invalid values are INVALID_ARGUMENT. Environment fallback applies only to session and timeout; explicit config supplies defaults below environment values. Screenshot format/quality affect only image persistence, not other command output.

`--content-boundaries` wraps only snapshot element rows and log entries in `--- BEGIN UNTRUSTED <source> <nonce> ---` / `--- END UNTRUSTED <source> <nonce> ---`. Source is `snapshot` or `logs`; nonce is 128 bits of lowercase hexadecimal generated by Random.secure per CLI invocation. Headings, counts, errors, hints, and diagnostics stay outside. JSON preserves strings and adds the same information as `contentBoundary: {nonce, source}` in the relevant data. This neither sanitizes content nor classifies instructions.

`--max-output` first finalizes the public observation, generation, and ref numbering for all elements, then returns only complete elements/entries that fit from the beginning. Text counts snapshot rows or JSON-serialized log entries; JSON counts each item's compact JSON in code points. Inter-item newlines/commas each count as one character. Envelopes, array brackets, headings, boundaries, and count metadata do not count. If the first item cannot fit, the array is empty. When enabled, the same data always includes `truncated` (bool), `originalCount`, and `omittedCount`. Omitted refs are removed from the session; guessing their numbers yields STALE_REF. The next snapshot does not rewind numbering. Workflow finalSnapshot follows the same contract. Image base64, saved images, stderr diagnostics, and the 64MiB IPC limit are unaffected.

Idle timeout is fixed at startup for the daemon's lifetime. Accepted forms include `10s`, `3m`, `1h`, `10000` (ms), and `10ms`. Negative/fractional values, unknown units, or values outside Duration/DateTime ranges are INVALID_ARGUMENT. Calls that omit it inherit the running value. An IPC call explicitly requesting another value fails during handshake with INVALID_ARGUMENT / not_sent before dispatch. Concurrent startups recheck after acquiring the startup lock and use only the first established setting. Help/version and workflow schema/validate finish locally without contacting a daemon.

Idle time starts only after all session queues and request deliveries are idle; running and queued work are not interrupted. Health probes can delay shutdown until safe but do not reset user inactivity. At expiry, normal shutdown finalizes recordings, discards all connections/refs, and releases the socket and lifetime lock. A recording alone does not prevent shutdown when request queues are idle. The next app operation returns NOT_CONNECTED and requires explicit connect and a new snapshot. The Flutter app itself is not terminated.

<a id="implemented-commands"></a>
<a id="実装済みコマンド"></a>

### Implemented commands

| Command | Behavior |
| --- | --- |
| `mcp [--tools <profiles>]` | Starts a stdio MCP server; default core, comma-separated profiles supported |
| `connect <uri>` | Connects the selected session; normalizes HTTP(S) VM Service URIs to WS(S) |
| `skills [list]` / `skills get <name> [name...] [--full]` / `skills get --all [--full]` / `skills path [name]` | Locally returns bundled Skill listings, content, and existing paths |
| `session list` | Lists session names and connection states; empty if no daemon exists |
| `session show` | Returns selected-session state, a redacted endpoint, and snapshot validity |
| `close [--all]` | Finalizes recording if present, then disconnects/discards the selected session (all sessions with --all). Absence also succeeds. Does not terminate the Flutter app |
| `snapshot` | Refreshes the observation and returns elements and refs |
| `get text <ref\|selector>` | Returns one element's observed text |
| `get box <ref\|selector>` | Returns one element's bounds in Flutter logical coordinates |
| `get count <selector>` | Counts exact observed candidates; refs are not accepted |
| `is visible <ref\|selector>` | Returns visibility as known/value; unobserved is unknown |
| `tap <ref>` / `tap <selector>` | Taps the target once |
| `tap --x <n> --y <n>` | Taps explicit coordinates once |
| `fill <ref> <text>` / `fill <selector> <text>` | Replaces input content; an empty string clears it |
| `swipe <ref> <direction> [--distance <n>]` | Swipes starting from an element; selectors also supported |
| `swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>` | Swipes from an explicit start to end |
| `scroll <ref> <direction> [--distance <n>]` | Sends a directional gesture to a scroll region; selectors also supported |
| `wait <selector> [--state exists\|gone] [--poll-interval <ms>]` | Waits for appearance/disappearance through observation only |
| `screenshot [--annotate] [path]` | Exclusively saves PNG (default) or JPEG. Explicit path > `--screenshot-dir` > temporary file. Annotation requires a supported provider and the latest valid snapshot |
| `logs` | Retrieves binding-collected logs without subscription or indefinite waiting |
| `record start <path> --platform <platform> --device <id>` | Starts device-screen recording without requiring VM Service |
| `record status` / `record stop` | Queries recording state / stops and waits for video finalization |
| `workflow schema [action]` | Returns bundled JSON Schema for the full workflow or an action; no daemon/connection needed |
| `workflow validate <path>` | Reads JSON/YAML and validates syntax, schema, and semantic constraints; no daemon/connection needed |
| `workflow run <path>` | Serially executes a workflow as one request on a connected session |

`<selector>` is exactly one of `--key <value>`, `--identifier <value>`, `--text <value>`, or `--type <value>`. Examples: `fill --key email 'a@example.com'`, `swipe --key pager left`. Mixing refs, selectors, and coordinates is an error. In addition to selectors, `wait` accepts ref and duration waits described under [Flutter extensions](#flutter-extensions), but never coordinates. Workflow v1 accepts selectors only. Pinned binding 0.6.0 has no identifier matcher, so identifier selection yields UNSUPPORTED_CAPABILITY.

Initial scroll support operates the specified region through the existing swipe mechanism. As with swipe, direction means finger movement, not content destination or guaranteed arrival. Scroll-to for off-screen elements is deferred.

Standalone `wait` defaults `state` to `exists` and also accepts `gone`. State and pollIntervalMs defaults apply only to omitted fields; explicit IPC null or invalid types yield INVALID_ARGUMENT before observation. `poll-interval` is an integer from 50 to 1,000ms, default 100ms. The first observation is immediate; the overall deadline uses common `--timeout`. `exists` succeeds with exactly one match and `visible != false`; multiple matches yield AMBIGUOUS_TARGET. `gone` succeeds with zero matches and keeps waiting for one or more. Text matching counts unverified-origin candidates as collisions; a sole unverified-origin candidate yields UNRESOLVABLE_TARGET.

`wait` polls only `inspect` on the same session queue. It sends no UI action and does not create, update, or invalidate public snapshots/refs. Successful data returns the awaited `state` and `requiresSnapshot:true`, directing the caller to a subsequent `snapshot` for current screen state and refs. Timeout or connection loss during wait follows the read contract: `outcome:not_sent`, with connection generation and refs discarded. Expiration before execution starts in the queue performs no observation and preserves the connection and refs.

<a id="screenshot-format-and-persistence"></a>
<a id="screenshotの形式保存"></a>

### Screenshot format and persistence

- Default unannotated PNG saves the backend's original bytes after decode validation, preserving dimensions and transparency. JPEG decodes PNG in the CLI, alpha-composites each pixel's RGB over white, then applies lossy compression without changing dimensions. PNG background-color metadata is not used.
- `--screenshot-format` accepts lowercase `png` or `jpeg`. `--screenshot-quality` accepts integers 0–100 only with JPEG, default 90. The pinned encoder compresses quality 0 like its minimum quality 1. Quality 100 is also lossy.
- PNG paths use `.png`; JPEG paths use `.jpg` or `.jpeg`. Matching is case-insensitive and preserves the supplied spelling. Format is not inferred from the extension. Mismatched or unknown extensions yield INVALID_ARGUMENT before connection. Missing extensions become `.png` for PNG or `.jpg` for JPEG.
- Omitting both path and `--screenshot-dir` saves `screen.png` or `screen.jpg` in a dedicated private temporary directory. Multiple images preserve backend order and add `-1`, `-2`, etc. before the extension: `screen.jpeg`→`screen-1.jpeg`, `screen-2.jpeg`. Automatic names follow the same numbering.
- Common `--timeout` is the original absolute deadline covering capture, transfer, decoding, white-background composition, JPEG conversion, and saving. It is checked before/after codecs, during composition, and during persistence; late success is forbidden. Immediate interruption of synchronous codecs or in-flight OS I/O is not guaranteed.
- Only after every image decodes/converts successfully are all destinations exclusively reserved and written. Existing files/directories/symlinks yield IO_ERROR. Conversion failure creates no output. Reservation/write failure or TIMEOUT attempts to remove every file and automatic directory created by this request, never preexisting files. OS cleanup refusal may leave partial artifacts, but no successful paths are returned. Deliberate replacement after reservation remains outside the guarantee.

<a id="workflow-v1"></a>

### Workflow v1

Workflow v1 executes `snapshot`, `tap`, `fill`, `swipe`, `scroll`, and `wait` in declared order from JSON or restricted YAML. `run` occupies one queue entry in one session for all steps and stops at the first failure. There is no rollback of completed steps, automatic retry, or mid-workflow resume.

Workflow targets accept selectors only, not refs or coordinates. Inputs bind through typed references, without string expansion, environment expansion, or shell execution. `--timeout` is an absolute deadline covering workflow/input reading, validation, daemon delivery, queue waiting, and every step.

Success returns workflow name, completed-step count, and `requiresSnapshot`. If the last snapshot obtained within the workflow has not been followed by a mutation, it is returned as `finalSnapshot`, with refs usable by subsequent CLI calls. Failure adds whether progress is known, completed-step count, and failed step to `error.details`. The [workflow v1 specification](workflow-file-spec.md) owns the detailed file schema, limits, and wait semantics.

<a id="session-lifetime-and-races"></a>
<a id="sessionの寿命と競合"></a>

### Session lifetime and races

- Connect or record start automatically starts the daemon when needed. App-operation commands never implicitly create an unconnected session.
- Connecting the same session to the same URI succeeds if its connection is healthy. Switching to another URI requires close first.
- Commands are serialized per session; different sessions are independent. Multiple sessions may not own the same normalized URI. Detecting aliases that reach the same app is not guaranteed.
- Connection loss marks a session disconnected and invalidates refs. Recovery requires explicit connect. Actions are never automatically resent.
- A daemon restart restores neither connections nor snapshots. Closing the last session shuts down the daemon.
- Timeout does not imply cancellation of an already-sent action. The result is unknown; the connection is discarded and reconnect/re-observation are required.

Single-session close waits for backend disconnection within the request deadline. A confirmed disconnect failure yields BACKEND_ERROR / failed (exit 1); timeout before confirmation yields TIMEOUT / unknown (exit 5). Both release connection ownership, invalidate refs, and discard the session. If an owned-app exit notification discarded the connection first, close uses that same disconnect result. Recording-finalization timeout retention and cleanup follow the recording contract.

<a id="state-queries-with-get"></a>
<a id="getによる状態照会"></a>

### State queries with get

`get text` and `get box` re-observe the target and share action uniqueness/ref-attribute checks. Zero selector matches yield TARGET_NOT_FOUND; multiple matches yield AMBIGUOUS_TARGET; an unissued, missing, or changed ref yields STALE_REF. A sole unverified-origin text selector yields UNRESOLVABLE_TARGET. Observed attributes can be read even for invisible elements, so action-only visibility checks do not apply.

Successful data is `{"text":string|null}` for text and `{"bounds":{"x":number,"y":number,"width":number,"height":number}|null,"unit":"flutter_logical_pixels"}` for box. Bounds are Flutter logical coordinates, not Simulator-image physical pixels. Missing values are null; actual empty strings and zeroes remain unchanged. This is not a contract for reading an input's value attribute.

`get count` returns `{"count":integer,"selector":{kind:value}}`. It counts exact key/identifier/text/type matches in the current inspect result; zero or multiple matches both succeed. Text uses candidateValue, counting each observed known-type or unverified-type text as one candidate. This does not guarantee the upstream action matcher's actual match count or actionability. Ref input is INVALID_ARGUMENT; a selector unsupported by the binding is UNSUPPORTED_CAPABILITY regardless of count. Successful get commands never update, invalidate, or reissue public snapshot generations/refs. Timeout and connection loss follow the existing read contract.

<a id="is-visible"></a>

### is visible

`is visible <ref|selector>` is a read command that re-observes once. Successful JSON `data` is one of `{"known":true,"value":true}`, `{"known":true,"value":false}`, or `{"known":false,"value":null}`. Unobserved nullable visibility is never coerced to false. Text output is respectively `Visible: true`, `Visible: false`, or `Visible: unknown`.

It uses shared target re-observation, uniqueness, and attribute comparison. Zero selector matches yield `TARGET_NOT_FOUND`, multiple matches `AMBIGUOUS_TARGET`, stale refs `STALE_REF`, and unsupported selectors `UNSUPPORTED_CAPABILITY`. A unique hidden target succeeds with false. Success neither performs UI actions nor invalidates/reissues refs or updates the public snapshot generation. It does not wait or determine enabled/checked state.

<a id="close---all"></a>

### close --all

`close --all` cleans up the entire daemon. Combining it with explicit `--session`, even default, is INVALID_ARGUMENT (exit 2). An absent/empty daemon also succeeds without automatic startup. Success has session:null and data:{closed:true,sessions:[per-session Result]}. Results are sorted by name and use the normal envelope (session, ok, data or error). Closed means local sessions were discarded, not that apps were terminated.

On receipt, it fixes the target-session set and stops accepting all new requests, including connect requests reserved before close. Queued requests are rejected before execution as CONNECTION_LOST/not_sent; running requests may finish until the common `--timeout` absolute deadline. Expiration invalidates connection generations. Sent actions return CONNECTION_LOST/unknown; unsent ones return not_sent. Late completion may not revive refs, send subsequent actions, or resend UI actions.

Recording finalization and disconnect are awaited per session within the deadline. Even partial failure discards every session's refs/URI ownership and shuts down the daemon. Partial failure has data:null and error.details:{closed:true,sessions:[per-session Result]}. Any timeout yields TIMEOUT (exit 5); other failures yield CLOSE_FAILED (exit 1). Aggregate outcome is unknown if any result is unknown, otherwise failed. Per-session results retain disconnect success, failure, or timeout. If IPC delivery itself is lost, outcome is unknown and per-session results are not guessed.

A new connect sent to a stopping daemon returns CONNECTION_LOST/not_sent. If handshake finds a stopping daemon, the existing startup/lifetime-lock path may wait for the next daemon, so close --all is not a barrier prohibiting future explicit connects. Subsequent use requires explicit connect and a new snapshot. Socket removal and lifetime-lock release use existing shutdown. Response delivery is limited to deadline+250ms; remaining clients are discarded within 250ms after shutdown. Post-deadline recording cleanup uses the existing 60-second shutdown limit plus five-second abort grace.

<a id="snapshots-and-element-references"></a>
<a id="snapshotと要素参照"></a>

### Snapshots and element references

Snapshot returns an observation generation and element list, including available type, text, key, identifier, bounds, and visible attributes. Missing attributes are never invented. Text output prioritizes target-selection information rather than all diagnostic properties.

`snapshot [--key <value> | --identifier <value> | --text <value> | --type <value>]` accepts at most one optional filter. Its value is a nonempty string matched exactly and case-sensitively against observed attributes. Multiple selectors, refs, unknown options, and empty values yield INVALID_ARGUMENT before observation. Unfiltered output is unchanged. Zero or multiple matches are both successful new snapshots and invalidate all old refs.

Filters are observational. `--text` matches display text, including unknown types. `--identifier` matches observed identifiers independently of backend action-selector support; absent attributes produce zero matches. Matching display text alone does not guarantee actionability. Actions separately require a verified supported selector, uniqueness across the full observation, and visibility.

Processing order is full observation → global uniqueness checks and ref numbering → filter → `--max-output`. Collisions outside the filter still affect ref safety, and numbering is not recomputed for the visible subset. Refs excluded by filtering or output limits are unusable (STALE_REF). Only filtered requests add `filter: {kind, value, matchedCount, totalCount}` to data. Kind is key/identifier/text/type, value is the supplied string, totalCount is all observed elements, and matchedCount is matches before the output limit. Text's Filter line reports the same conditions/counts. Filtering itself does not imply truncated. With `--max-output`, originalCount is the filtered count (matchedCount), and omittedCount counts matches omitted by the budget. Filter metadata is outside the character budget. Workflow v1 snapshot-step syntax is unchanged.

Refs are valid only for the selected session's latest snapshot. A new snapshot, reconnect, or disconnect invalidates existing refs. Immediately before sending a UI action to the backend, all refs are invalidated; success, failure, and unknown outcomes all require another snapshot. Argument-validation-only failure does not invalidate them. Successful wait, screenshot, logs, and state queries do not invalidate them.

Ref numbers increase monotonically across the daemon's lifetime and are never reused across sessions. After a daemon restart, always start again with connect and snapshot.

Immediately before an action, re-observation checks that the stored selector matches uniquely and that type, identifying attributes, text, and bounds have not changed. Mismatch yields STALE_REF; multiple matches yield AMBIGUOUS_TARGET. Refs never automatically fall back to coordinates. Explicit selectors also have their observed match counts checked.

Prefer key and identifier; use text/type when their correspondence to backend matching is verified. Semantics display text is not equivalent to matcher text. Elements without a uniquely actionable selector still expose information and a reason, but no action ref.

Pinned binding 0.6.0 exposes no text-origin attribute, so text matching is limited to verified type names Text, RichText, EditableText, TextField, and TextFormField. Text from Semantics-derived or other custom types is display information; use a key or unique type for actions.

Uniqueness includes unverified-origin text. If an unknown type has the same text, text selection of a known type, text-derived refs, and wait exists also yield AMBIGUOUS_TARGET. Snapshot uses a safe key/type for ref issuance when available.

Existing APIs do not make re-observation and action atomic, and some elements are absent from observations. Changes between those operations or replacement by an element with identical attributes cannot be fully detected. The initial release performs preflight validation within these limits and does not guarantee persistent Flutter element IDs.

<a id="swipe-details"></a>
<a id="swipeの詳細"></a>

### Swipe details

- Two modes: element and coordinates. Directions are left, right, up, and down.
- Distance is finite and positive, default 200. Coordinates are finite and nonnegative. Units are Flutter logical pixels, distinct from image physical pixels.
- Coordinate mode requires all four coordinates and rejects identical start/end points. Mixing element-mode options is also rejected.
- Speed, duration, inertia, and system gestures such as iOS Home are out of scope.
- Success means backend gesture processing completed. Verify results such as page changes with the next snapshot.

<a id="output-and-exit-codes"></a>
<a id="出力と終了コード"></a>

### Output and exit codes

Except for `skills` and a running `mcp`, JSON success and failure use the envelope below. Initial schemaVersion is 1. Session-independent commands use session:null; exactly one of data/error is nonnull. Help/version use the same envelope in JSON mode. Skill distribution, including `skills --help`, follows its dedicated compatibility contract below. `mcp` startup-argument errors use the normal CLI contract; after startup, stdout is reserved for MCP messages.

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{"requiresSnapshot":true},"error":null}
```

```json
{"schemaVersion":1,"ok":false,"session":"demo","data":null,"error":{"code":"STALE_REF","message":"Target changed","hint":"Run snapshot again","outcome":"not_sent"}}
```

Outcome is not_sent, failed, or unknown. Connection loss or timeout after sending is never treated as proof that execution did not occur.

Normal text output also shows outcome for every error. If the daemon processes a request but cannot deliver its result, for example because a response exceeds the size limit, even normal commands return unknown rather than reverting to not_sent.

| Exit code | Error category and representative codes |
| --- | --- |
| 0 | Success |
| 2 | Arguments: INVALID_ARGUMENT |
| 3 | Connection/session: NOT_CONNECTED, SESSION_CONFLICT, CONNECTION_LOST |
| 4 | Target: TARGET_NOT_FOUND, AMBIGUOUS_TARGET, STALE_REF, UNRESOLVABLE_TARGET |
| 5 | Deadline: TIMEOUT |
| 6 | Missing capability: UNSUPPORTED_CAPABILITY |
| 1 | Other: BACKEND_ERROR, IO_ERROR, INTERNAL_ERROR |

<a id="screenshot-storage"></a>
<a id="screenshotの保存"></a>

### Screenshot storage

Screenshot data contains an array of absolute `paths`. Destination precedence is explicit path, common `--screenshot-dir <path>`, then the existing private temporary directory. An explicit path bypasses existence/permission checks on the directory option. Directory configuration is per invocation, never persisted in daemon/session, and does not affect other commands. Empty or NUL-containing directory values are INVALID_ARGUMENT.

Relative explicit paths and directory paths are normalized against the caller CLI's cwd. The explicit path's parent and specified directory must already exist; neither is created automatically. A missing specified directory, regular file, symlink at the directory itself (including dangling), or inadequate save permissions yields IO_ERROR. Ancestor-directory symlinks may be resolved. Deliberate replacement after the directory type check is outside the guarantee.

Directory mode generates `screen-<32 hex digits of 128-bit randomness>.png` directly inside it (`.jpg` for JPEG). Sequential/concurrent captures generate distinct names per request, with exclusive creation preventing overwrite. Even a generated-name collision with an existing path yields IO_ERROR. Omitting both retains `screen.png` or `screen.jpg` inside a unique `marionette-screenshot-*` temporary directory.

Multiple images add `-1`, `-2`, etc. before the explicit/generated name's extension (missing extensions become `.png` or `.jpg` for the selected format). All PNGs are decode-validated and all destinations exclusively created before writing. Existing files, directories, and symlinks are rejected. Partial failure deletes image files created by this request and, for temporary storage, its temporary directory. The specified directory and existing artifacts are never removed. Cleanup failure does not replace the original error or return successful paths. Deliberate destination replacement by another process after reservation is outside the guarantee. Empty or invalid PNG data yields BACKEND_ERROR, an expired save deadline TIMEOUT, and other persistence failures IO_ERROR. As screenshot is a read, these errors retain outcome:not_sent.

Logs normalize the returned range and explain when unavailable collection cannot be distinguished from zero entries. URI credentials and input strings never appear in diagnostic logs.

`screenshot --annotate` composites only actionable refs actually published by the latest snapshot into a new PNG as `@eN` labels and boxes; JPEG output converts after composition. It neither accepts an existing PNG as input nor alters original image bytes. The destination is a new annotated-image path using normal screenshot exclusive storage and overall deadline rules. Successful data adds annotated=true, generation, annotationCount, and skippedAnnotations to paths. It neither numbers, updates, nor invalidates refs. Invalid snapshots or changes in target uniqueness/attributes during re-observation before/after capture produce STALE_REF without saving. Observation and capture are not atomic upstream, so animation that changes and returns to the original state may go undetected. Use a stationary screen.

The normal screenshot response from pinned `marionette_flutter: 0.6.0` cannot establish image/view, scale, or orientation correspondence. Annotation requires the separate opt-in `marionette_agent.captureMappedScreenshot` provider. This limited contract returns image and geometry v1 together; it does not mean general annotation support in the pinned binding. The example's debug configuration implements it. Supported geometry is one view, origin (0,0), zero rotation relative to logical bounds, and explicit logical and PNG width/height. Portrait/landscape use current dimensions without inferred rotation. Missing registration, multiple views/images, rotation, or dimension mismatch yield UNSUPPORTED_CAPABILITY without saving annotations. Scale is never inferred from bounds or image appearance.

Missing/nonfinite bounds skip a ref as missing_or_invalid_bounds. Nonpositive width/height or any portion outside the view skips it as bounds_outside_view. Reasons go into skippedAnnotations; bounds are never clamped into the view. Labels are positioned without overlapping each other, and displaced labels connect to targets with lines. Insufficient placement space skips a label as label_space_exhausted. A valid snapshot and geometry can save annotationCount=0 even with no actionable refs.

<a id="verification-criteria"></a>
<a id="検証基準"></a>

## Verification criteria

1. Connect from macOS to iOS Simulator and complete snapshot→tap/fill/swipe→snapshot across separate CLI processes.
2. Isolate two sessions' connections, refs, and disconnects, and serialize concurrent requests within one session.
3. Return the specified JSON and exit codes for stale refs, ambiguous targets, connection loss, and timeout, without automatic action resending.
4. Verify PageView changes and Dismissible dismissal with swipe, including coordinate mode on Simulator.
5. Run wait, scroll, PNG/JPEG persistence, and log retrieval through shared session, deadline, and error contracts.
6. Verify JSON/YAML workflow validation, binding, queue occupancy, wait, failure progress, and final-snapshot handoff through automated tests and Simulator.
7. For code changes, run format, analyze, and relevant tests from the repository root. When CLI contracts change, run `example/` on iOS Simulator and check both product CLI results and the resulting screen state.

Unit, IPC, and contract tests live in `test/`; Simulator scenarios live in `integration_test/`. Passing FakeBackend tests alone does not replace Simulator verification.

<a id="bundled-skill-distribution"></a>
<a id="同梱skillの配信"></a>

## Bundled Skill distribution

`skills` is a local read command adopting agent-browser's bundled Skill design. It does not connect to an app, create a runtime, start/query a daemon, download, generate Skills, or install them into agent settings. It does not execute `--restore` or action policy, sharing only common-option parsing/value validation and `--debug`. It is not added to batch/workflow/IPC actions.

- `skills` and `skills list` list entries by name. Text descriptions are truncated at a word boundary near a maximum of 70 UTF-8 bytes; JSON returns the full description.
- `skills get <name> [name...]` returns complete SKILL.md files, including frontmatter, in requested order. `--full` appends readable text files directly inside each Skill's references/ and templates/, sorted by directory then filename. It neither recursively scans nor executes files.
- `skills get --all` retrieves all nonhidden Skills in name order and supports `--full`. `--all` takes precedence over explicit names.
- `skills path` returns search directories one per line; `skills path <name>` returns the matching Skill directory. Lookup uses frontmatter name, not directory name.
- `skills --help` / `-h` displays dedicated help. `--json` works before or after the command. Shared validation rejects unknown/duplicate options and extra arguments.

`skills/marionette-agent/SKILL.md` is an introductory stub with `hidden: true`. `skill-data/core/` and `skill-data/simulator-verify/` contain runtime guides and supporting references/templates. A simple parser reads name, description, and hidden from SKILL.md in immediate subdirectories. Indented description continuation lines join with spaces; hidden recognizes true/yes. Missing/empty names, malformed frontmatter, and unreadable entries are ignored. Frontmatter boundaries must be standalone `---` lines; LF and CRLF are accepted. Hidden entries are excluded from list/--all but can be retrieved by explicit name with get/path. An empty list succeeds; no get targets or unknown names fail. Duplicate names remain in the listing; explicit lookup uses the first in discovery order.

An existing `MARIONETTE_AGENT_SKILLS_DIR` (one parent directory of Skills) has highest discovery priority. Invalid/missing overrides fall back to normal discovery. Normal discovery resolves executable symlinks and uses skills/ and skill-data/ in a distribution root with skills/ two levels above the executable, or an ancestor root with skills/. Dart execution can fall back to resolving the package root through its package URI, never selecting a different package from the caller's cwd. Installed/upgraded binaries prefer their embedded version-specific bundle adjacent to the executable over normal discovery. A missing embedded bundle does not fall back to another version.

Install/upgrade copies both directories from the selected checkout into a dedicated `.marionette-agent-*` bundle inside the bin directory before compiling. Only the relative bundle name is embedded, and only a successful binary is installed, so the result can move without the source checkout. Distribute the binary together with its matching hidden bundle. Failure removes the new bundle and owned reservation, retaining the pre-upgrade binary. Old bundles are not automatically deleted so running older binaries remain consistent. Manual compilation requires a distribution root containing skills/, skill-data/, and bin/, or an explicit environment override. Source symlinks and special files are rejected because they cannot guarantee self-contained distribution.

For compatibility, skills alone uses `{"success":true,"data":...}` or, on failure, `{"success":false,"error":"description"}`. List returns an array of name/description; get returns name/content entries, with a files array of path/content when --full includes supporting files; path returns an object with a paths array or a name/path object. Dedicated help uses data.help. It adds no session/schemaVersion/outcome. Text failures go to stderr; JSON writes one object to stdout. Success exits 0; argument errors identified as skills, unknown names, discovery failures, and timeouts exit 1. Failures from missing `--config`, invalid JSON, or unknown options use the same format and exit code. Normal-command JSON and exit codes remain unchanged. The shared timeout is checked before/after reading, without guaranteeing immediate interruption of synchronous filesystem I/O.

<a id="out-of-scope-and-future-work"></a>
<a id="対象外将来範囲"></a>

## Out of scope and future work

Find supports role/label/placeholder, and get value/is enabled/is checked have been added. Normal selectors remain key/identifier/text/type. Hint/tooltip, a complete Semantics tree, and persistent target IDs are unsupported. The [Issue #14 proposal](semantics-selector-state-design.md) remains the original stock-binding investigation and future design.

Formal support for physical iOS/Android devices or other host OSes, physical-iOS recording, Linux/Windows recording, an arbitrary-extension CLI, hot reload/restart, long-press/pinch, and arbitrary app-state restoration remain out of scope. Workflow v1's schema is preserved.

<a id="stdio-mcp-server"></a>
<a id="stdio-mcpサーバー"></a>

## stdio MCP server

`marionette-agent mcp [--tools core,inspect,actions,workflow,record|all]` processes newline-delimited JSON-RPC through the server API in `dart_mcp: 0.5.2`. Protocol negotiation, initialize/initialized, ping, and stdio disconnection follow the SDK. Startup and tool discovery alone start neither daemon nor app. Tools/list and tools/call are available after initialization completes. Resources, prompts, and HTTP transport are not provided.

The default profile is core. Comma-separated profiles combine with duplicates removed. All enables every published MCP tool, not compatibility with every CLI syntax. Unknown/empty profiles are INVALID_ARGUMENT. Tool names use the `marionette_agent_` prefix. See [CLI runtime details](cli-reference.md#mcp) for profile scope and input contracts. Tools/list returns up to 20 entries with nextCursor for continuation. Unpublished/disabled tools and invalid cursors yield JSON-RPC -32602. Tools have typed inputSchema and readOnly/destructive/idempotent/openWorld annotations.

UI targets are `target: {ref: "@e1"}` or an object containing exactly one of key/identifier/text/type. Common fields are session, timeoutMs, maxOutput, and contentBoundaries. Tool fields override common-option defaults supplied at startup. Namespace, action policy, confirm-actions, and idle settings are inherited from startup. Inputs become argv for fixed CLI commands and never pass through a shell. Arbitrary command arrays and extraArgs are not exposed. Workflow/batch accept file paths and reject stdin `-`. MCP startup rejects `--restore` and `--confirm-interactive`.

Each tool call invokes the same executable/Dart entrypoint once with `--json`, sharing CLI session, ref invalidation, queue, deadline, policy, and error-outcome contracts. Independent CLI calls can use the same runtime/session. Success or failure from CLI-invoking tools appears in text and `structuredContent: {exitCode, response}`, preserving the CLI envelope inside response. A nonzero exit or ok:false sets isError:true. Schema-invalid input yields INVALID_ARGUMENT without echoing values. CLI launch failure yields IO_ERROR / not_sent; malformed responses after launch or MCP-side timeout yield IO_ERROR or TIMEOUT / unknown, without automatic resend. CLI execution receives five seconds of startup/cleanup grace beyond the request timeout without changing the CLI's own deadline. Captured stdout is capped at 64MiB. Only tools_profiles returns profile information directly without invoking CLI.

Screenshot returns MCP PNG/JPEG ImageContent alongside the CLI envelope containing saved paths, up to 16MiB total. Exceeding the limit or failing to read images preserves the save result and reports omitted inline images in text. App-derived snapshot/log content is untrusted data.

MCP traffic, authenticated URIs, and input strings are never logged as diagnostics. Child CLI stderr is not forwarded into MCP responses. Stdin EOF terminates the MCP server and its owned running CLI processes. The independent daemon and existing sessions retain normal CLI lifetimes; call close to disconnect them. SDK cancellation is unsupported, so disconnection does not imply rollback of actions already executed.

<a id="flutter-extensions"></a>
<a id="flutter向け拡張"></a>

## Flutter extensions

The [additional command specification](cli-parity.md) forms part of this specification. It defines syntax, output, and scope for snapshot interactive/compact/depth, typed get/is, find, additional interactions, ref/duration waits, crop/diff, clipboard, config/namespace, connection state, batch/policy, record restart/fps, device list, extra doctor modes, and install/upgrade.

Typed mounted-Widget observation is enabled only when the optional `marionette_agent_util/flutter.dart` provider is present. Attributes with unknown provenance are never inferred. Ref matching, uniqueness, invalidation immediately before send, and no automatic resend retain existing contracts. UI actions and role/label searches are limited to the provider's declared scope; atomic re-observation/send and complete clipping/occlusion detection are not guaranteed.

IPC protocolVersion is 7, adding managed-app launch and shutdown on close. Requests include optional session action policy. Public schemaVersion stays 1, with expanded data for launch and session information displaying owned apps. Close an old daemon using the old CLI before switching to the new CLI.

<a id="device-screen-recording"></a>
<a id="端末画面録画"></a>

## Device-screen recording

`record --platform ios/android/macos/web` captures an entire device/display. It is independent of VM Service and the Marionette binding, so it can capture release apps and screens outside the app. OS-protected content is not guaranteed. Audio is not recorded.

| platform | device | Format and prerequisites |
| --- | --- | --- |
| ios | UDID of a booted iOS Simulator | `.mp4`, macOS and Xcode. Physical iOS devices and ambiguous aliases such as `booted` are unsupported |
| android | Online, authorized adb serial | `.mp4`, Android platform-tools; standard screenrecord on Emulator/physical device |
| macos | Display number starting at 1 | `.mov`, standard macOS screencapture and Screen Recording permission for the invoking app |
| web | `display:<index>@ws://127.0.0.1:<port>/devtools/page/<id>` | `.mov`, macOS, visible Chrome, a dedicated debug profile, and Screen Recording permission; captures the entire explicit display |
| flutter | Omitted in CLI; result uses session name | `.mp4`, a connected Marionette debug app and ffmpeg; saves in-app rendering, including hidden execution environments |
| linux / windows | Any | Unsupported; internal API throws UNSUPPORTED_CAPABILITY and CLI exits 6 |

- Platform/path are required. Flutter forbids device; other platforms require it. Unknown platforms, malformed devices, and extension mismatches are INVALID_ARGUMENT. Unsupported platforms are also validated by the CLI and rejected before daemon startup.
- Relative paths become absolute against the caller CLI's cwd. The parent directory must exist and be writable. Existing files/directories/symlinks yield IO_ERROR and are never automatically overwritten.
- One recording per session and one per device within the same daemon. Reservations apply during startup and stopping too; conflicts yield SESSION_CONFLICT. After stopping, the same session can start another recording at a new destination.
- Start launches the daemon if needed and retains a session as recording owner. An unconnected recording session is disconnected with URI:null. Once recording starts successfully, the session remains until close.
- Start returns after startup confirmation; ongoing recording does not occupy the session queue. iOS confirms the first-frame notification; Android confirms output-header creation. Standard macOS capture has no first-frame event, so it checks one second of process liveness and verifies actual video creation on stop.
- `--timeout` bounds start/stop requests, not recording duration. Backend startup waits at most 30 seconds. On startup timeout, late-created handles are still stopped and reservations reclaimed; the device cannot be reused until termination is confirmed. Bounded stop/cleanup continues after a stop timeout; inspect status for the result. TIMEOUT has outcome:unknown. Neither UI actions nor recording are automatically resent.
- Android automatically stops after 180 seconds, retrieves video to the host, and updates state. It does not split, restart, or concatenate automatically. Correct recording during rotation is not guaranteed.
- Stop waits for process termination, video finalization, required retrieval, and persistence. Confirmed stop/save failures have outcome:failed; timeout has outcome:unknown. Duplicate stop returns the same result. Without a recording, the result is `{recordingState: idle}`. Status/stop do not start a missing daemon.
- Recording start/stop/status neither invalidates refs nor changes VM Service connections. Device recording can continue through hot restart or connection loss.
- Close finalizes recording before discarding the connection and includes final state in data.recording. Even if recording has already failed, close releases ownership and returns recordingState:failed with failure information.
- Normal daemon shutdown, including SIGINT/SIGTERM, waits up to 60 seconds for recording finalization. On expiration, it force-stops owned recording processes and bounds additional cleanup waiting to five seconds. Unfinalized videos and reservations remain for recovery and are never reported as success. Late-returned startup handles are also force-stopped. Cancellation of in-flight OS file I/O and forced stop on disconnected Android devices are not guaranteed. Automatic recovery after SIGKILL or host shutdown is out of scope.

Successful data contains recordingState (idle/starting/recording/stopping/stopped/failed), platform, device, path, startedAt, elapsedMs, and bytes. Idle contains only recordingState. StartedAt is UTC startup-confirmation time; elapsedMs is wall-clock time from then until finalization, not media duration. Bytes is finalized video size. Failed status includes failure and recoveryPath. Stop returns failure with a nonzero exit.

The internal package saves within the daemon; video does not travel through IPC. It exclusively reserves the destination, records into private staging under the same parent directory, then writes the finalized video into the reservation. Startup failure reclaims this request's reservation; finalization failure retains staging for recovery. Deliberate replacement of a reserved destination by another process is outside the guarantee.

Verification status: product CLI checks have covered iOS Simulator, Android Emulator, and the main macOS display. macOS checks included start, status, stop, duplicate stop, rejection of existing files, finalization by close, full-frame decoding of the generated MOV, and screen changes.

<a id="headless-flutter-app-recording-issue-20"></a>
<a id="flutterアプリのヘッドレス録画issue-20"></a>

### Headless Flutter app recording (Issue #20)

`record start <new.mp4> --platform flutter [--fps 1..60]` requires a prior connection to the selected session's VM Service. No connection yields NOT_CONNECTED; unsupported backends or multiple views yield UNSUPPORTED_CAPABILITY. Supplying CLI `--device` is INVALID_ARGUMENT. Result platform is flutter and device is the session name. Recording is exclusive per session without preventing explicit recording of the same app through another session. Restart, status, stop, close, save protection, and request deadlines use shared contracts.

A dedicated read connection continuously captures PNGs from the actual app. Start returns only after the first PNG is confirmed. Default fps is 10; 1–60 specifies the waiting interval after each completed capture. Capture/save time is additional, so the requested capture frequency is not guaranteed. Actual capture timestamps produce silent H.264 MP4 with VFR (variable frame rate). Fast animations may be missed. Images are saved sequentially to private staging; ffmpeg conversion on stop is bounded to 30 seconds. Temporary disk space grows with recording duration. Missing ffmpeg yields UNSUPPORTED_CAPABILITY; invalid PNG or conversion failure yields IO_ERROR; capture failure marks recording failed instead of substituting white frames and claiming success. Image-size changes stop recording with UNSUPPORTED_CAPABILITY.

The target is a single Flutter-rendered view. OS keyboards/dialogs, browser UI, and platform-view capture are not guaranteed. Screen Recording permission is unnecessary, but the app needs the Marionette debug binding. Stopping recording does not affect the action connection, refs, or held keys. Loss of the recording connection fails without reconnection/resend. Losing only the action connection does not close the recording connection. Continuation through hot restart is not guaranteed.

Headless means starting each platform's execution environment without showing it. iOS boots/installs/launches a Simulator in a private device set, separate from Simulator.app, without opening a display window. Android uses Emulator `-no-window`; Web uses Flutter `--web-run-headless`. macOS keeps a real FlutterEngine in a hidden NSWindow and explicitly enables debug-only `enableHeadlessRendering()` for hidden-frame production. macOS requires a logged-in GUI session; hosts without WindowServer are outside the verified scope. Connect to a manually started app owns neither app nor device. Launch starts through util, and close stops the owned environment. See the [headless guide](headless.md).

<a id="web-recording-scope-and-connection"></a>
<a id="web録画の範囲と接続"></a>

### Web recording scope and connection

`--platform web` targets visible Google Chrome on macOS. Use `--platform flutter` above for hidden Flutter Web rendering. Device combines a display number from 1 to 999 and a page WebSocket endpoint chosen from Chrome's `/json/list`, as `display:1@ws://127.0.0.1:9222/devtools/page/<ID>`. Ports are 1–65535 and IDs uppercase alphanumeric. Localhost, remote hosts, credentials, query, fragment, browser/worker endpoints, and leading zeroes are rejected. The user starts Chrome with a dedicated `--user-data-dir` and loopback `--remote-debugging-port`. Other browsers, headless Chrome, and non-macOS hosts are unsupported. Missing protocol capabilities yield UNSUPPORTED_CAPABILITY; disabled debugging/connection refusal yield CONNECTION_LOST; protocol rejection yields IO_ERROR. Raw server messages are not printed.

Standard screencapture records the entire selected display to MOV, including Chrome's address bar, tabs, settings, OS dialogs, and other apps on that display. This is neither tab-only video nor Flutter-rendering capture, and it has no audio. The user places Chrome on the selected display; the CLI neither moves nor follows windows. Moving Chrome to another display does not change the recorded display. Hidden/minimized windows and dialogs on other displays are absent; occluding content is captured. Protected content is not guaranteed.

CDP verifies Chrome page identity and monitors Inspector termination and WebSocket disconnection. Capture shares macOS backend startup confirmation, stop, and permission contracts. The invoking macOS app needs Screen Recording permission; denial or an invalid display yields IO_ERROR with a settings hint. Permissions are not changed automatically and permission dialogs are not bypassed. Normal Web interaction is performed by the user or existing browser controls; this adds no Web tap/fill. Recording neither depends on VM Service nor blocks normal CLI actions.

Tab closure, crash, or debug-connection loss ends recording with CONNECTION_LOST and changes status to failed. Stop exits nonzero; close returns final state including failure. Partial video stays at recoveryPath rather than switching tabs and claiming success. Explicit stop/close finalize normally. Startup/stop races and timeout use the common contract. Within one daemon, a display is exclusive across Web tabs and macos recording. Exclusion across other daemons or external recorders is not guaranteed.

See [Web recording approaches](web-recording.md) for API comparisons, selection rationale, and references.

At Web startup, CoreGraphics `CGPreflightScreenCaptureAccess` is read through Dart FFI. Missing permission yields IO_ERROR before Chrome connection or native recording. No permission-request API is called. An unavailable API yields UNSUPPORTED_CAPABILITY.

<a id="hybrid-execution-environments-issue-20-extension"></a>
<a id="ハイブリッド実行環境issue-20追加仕様"></a>

## Hybrid execution environments (Issue #20 extension)

`launch <project> --platform tester|ios|android|macos|web` builds and starts a debug app in the selected environment on a macOS host, connects it to the same session, and confirms the first inspect. Standard connection data adds application:{platform,state,pid,device?}. Session show/list also display owned apps. URIs follow existing redaction rules.

The Flutter executable is --flutter (default: daemon PATH); entrypoint is --target (default lib/main.dart). Project becomes absolute against CLI cwd. Only iOS requires --device-type and --runtime; only Android requires --avd and an even --port (5554..5682). Fields for other environments and unknown fields are rejected by both CLI and daemon. Users prepare SDKs, AVDs, and project dependencies beforehand; launch uses --no-pub. The request timeout covers build, startup, connection, and observation.

Launch can start the daemon automatically and shares the session queue and action policy. Existing connections, owned apps, or recordings in the session, a managed project, or an occupied Android port yield SESSION_CONFLICT. A project's real path and an OS file lock enforce exclusion to prevent competing build outputs. There is no automatic fallback to another environment, action resend, or automatic restart.

Startup belongs to marionette_agent_util. Tester/Web/macOS own a Flutter runner, iOS a unique private device set, and Android a process for the explicit AVD with -no-window -no-snapshot -read-only. macOS apps require opt-in hidden-window support. The CLI calls shared util APIs instead of assembling environment variables or OS commands.

Close finalizes recording, stops the launched environment, and discards the connection. Connect to an external app closes only the connection. Close --all and daemon shutdown also reclaim owned resources. App exit invalidates the connection generation and refs. Startup/readiness failure or timeout cleans up owned processes, devices, and URIs; cleanup may continue past the request deadline. Per-process shutdown allows eight seconds for normal exit, three for TERM, and three for KILL; iOS device cleanup is bounded to 30 seconds. Unconfirmed shutdown is not success, and temporary storage remains. Shared devices and the adb server are untouched. Automatic recovery after SIGKILL or host shutdown is out of scope.

Tester's supported SDK is Flutter 3.47.2, debug only, with logical size 800×600 and DPR 3. It does not guarantee equivalent OS-native features, Web execution semantics, or physical-device performance; verify those in each actual environment. Every environment shares existing session operations and record --platform flutter. See the [headless guide](headless.md) for procedures and limitations.
