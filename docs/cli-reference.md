# CLI runtime details

[日本語](ja/cli-reference.ja.md) · [Documentation index](README.md)

Basic syntax, command lists, and installation examples live in the [public reference](https://r0227n.github.io/marionette_agent/en/reference/commands/). This supplement covers script integrations, MCP clients, and precise output handling. See [advanced operation details](cli-parity.md) and the [workflow file reference](workflow-file-spec.md) for their respective contracts.

<a id="arguments"></a>
## Arguments and diagnostics

Duplicate common options and missing values are argument errors. Everything after `--` is positional and is not reinterpreted as an option. Session and timeout precedence is explicit CLI, environment, explicit config, then defaults. Only the selected value is validated; invalid values do not silently fall back. An environment value overridden by CLI is ignored even if invalid.

Syntax errors still recover a valid session and JSON setting. Invalid sessions, session-independent commands, and `close --all` return `session:null`. The timeout is an absolute deadline including input loading, startup, and queue time. Its value must be a positive integer representable by Duration/DateTime.

`--debug` applies per request. It records the stages reached among `cliParsed`, `runtimePrepare`, `daemonOpen`, `daemonStart`, `daemonReady`, `requestSend`, `daemonDispatch`, `sessionQueue`, `commandExecute`, `daemonResult`, and `cliResult`. `elapsedMs` measures each interval; daemon diagnostics appear when the response arrives. Diagnostics send request ID, session, stage, time, and normalized error code to stderr, excluding authenticated URIs, input values, selector values, app text, and stack traces. Do not put secrets in session names.

<a id="output"></a>
## Untrusted content and output budgets

Text boundaries from `--content-boundaries` surround only snapshot elements or log entries. Each request uses a random 128-bit hex nonce. Headings, hints, counts, and diagnostics remain outside. These boundaries do not turn app strings into trusted instructions.

JSON preserves strings and adds `contentBoundary:{nonce,source}` to the relevant data, with source `snapshot` or `logs`. `--max-output` always adds `truncated`, `originalCount`, and `omittedCount`.

The budget counts Unicode code points: element lines or JSON-encoded log entries in text mode, and compact JSON for each item in JSON mode. Separating newlines/commas count; the envelope, array brackets, headings, boundaries, and count metadata do not. Complete items are retained from the start until the next item cannot fit. Quotes and escaping count, so text and JSON may retain different item counts.

Uniqueness checks and ref numbering use the entire observation before filtering and budgeting. Omitted refs cannot be used. A filter adds `filter:{kind,value,matchedCount,totalCount}` outside the budget; `originalCount` is the filtered count. Filtering alone is not truncation. Snapshot text/identifier filters compare observed attributes without guaranteeing that the corresponding action selector is supported.

The budget also applies to workflow `finalSnapshot`. Images, other command results, stderr, and the 64 MiB IPC frame limit are separate. Get/is queries preserve published refs; missing text/bounds remain null, while actual empty strings and zero values remain intact. `get count` counts observed candidates, not actionable elements.

<a id="lifetime"></a>
## Daemon lifetime and shutdown

The idle timeout is fixed at daemon startup. Requests that omit it inherit the existing value; explicitly selecting a different value is rejected before dispatch. `0` disables automatic shutdown. Close all sessions before starting with a new value. Execution, queued requests, and response delivery prevent idle shutdown; health probes do not extend the deadline. Recording alone is subject to idle shutdown.

Shutdown finalizes recording and releases sessions, refs, sockets, and locks. It cleans up runners owned by `launch` and leaves externally started apps attached through `connect` running. A subsequent operation needs an explicit connection and a new snapshot.

If recording finalization times out during a selected-session close, the session remains available for `record status` and a later close. Disconnect failure or timeout discards the session and refs. `close --all` proceeds with daemon shutdown even when recording finalization times out. Per-session results are sorted by name in `data.sessions` on success or `error.details.sessions` on partial failure. Any timeout yields exit 5, other failures exit 1, and full success exit 0. See [SPEC](SPEC.md#close---all) for the complete contract.

<a id="doctor"></a>
## Doctor results

Ordinary checks are read-only: host, runtime ownership/mode 0700/path length, daemon protocol, dependency constraints and locked versions, and available iOS Simulators. A runtime that does not exist is a normal unperformed check. Only explicit `--probe-uri` opens a dedicated app connection, released afterward. Binding version is not inferred without a real response.

Checks return `success`, `failure`, `unknown`, or `skipped`. A completed diagnostic can return `ok:true` while failure/unknown checks set `data.exitCode` and the process exit code to 1. Internal diagnostic timeouts mean unknown/exit 1; argument errors exit 2. Unstarted checks become unknown after the overall deadline; daemon handshake waits at most one second.

`--quick` checks only host/runtime/daemon; `--offline` skips the VM probe. `--fix` only repairs the mode of an existing runtime directory owned by the current user to 0700. It does not handle symlinks, other owners, SDK installation, socket removal, or daemon startup.

<a id="mcp"></a>
## MCP stdio server

Start with the [agent integration guide](https://r0227n.github.io/marionette_agent/en/guides/agents/). Combine profiles with commas. Tool names share the `marionette_agent_` prefix.

| Profile | Tool suffixes |
| --- | --- |
| `core` (default) | connect, launch, snapshot, tap, fill, swipe, scroll, screenshot, get_text, get_box, get_count, is_visible, wait, close, session_list, session_show, session_bind |
| `inspect` | get_value, is_enabled, is_checked, logs, doctor, device_list |
| `actions` | dblclick, focus, hover, check, uncheck, scrollintoview, type, select, press, keydown, keyup, keyboard_press, keyboard_type, keyboard_inserttext, clipboard_read, clipboard_write, clipboard_copy, clipboard_paste, drag |
| `workflow` | workflow_run, workflow_validate, workflow_schema, batch, confirm, deny |
| `record` | record_start, record_restart, record_stop, record_status |
| `all` | All of the above |

`marionette_agent_tools_profiles` is always available. Find/diff/state/skills/install/upgrade are not exposed through MCP. `tools/list` returns up to 20 tools; pass its `nextCursor` as the next `cursor`. Omitted/null means the first page; invalid values or types return JSON-RPC `-32602`. Tools in disabled profiles cannot be called.

Use each tool’s `inputSchema` as the input definition. A `target` contains exactly one of ref/key/identifier/text/type. Per-request `session`, `timeoutMs`, `maxOutput`, and `contentBoundaries` override startup settings. Connection, target resolution, policies, and ref expiration follow the CLI contract.

`session_bind` associates platform/device with the session. Normal snapshot/tap/swipe accept the configured sources: `@e` refs route to Flutter and `@n` to native. Native selectors/coordinates use `source: native`; unqualified selectors remain Flutter. Native key targets are unsupported. Native tap/swipe retain the `native` action policy in addition to tap/swipe. The old native tools/profile are removed.

CLI tools return `{exitCode,response}` in text and `structuredContent`, where response is the normal CLI envelope. Failures set `isError:true` and preserve code/outcome. Tools_profiles returns profile information directly. Inline screenshot images are limited to 16 MiB total; oversized or unreadable images yield saved paths and an omission reason.

Startup `--restore` and `--confirm-interactive`, and workflow/batch stdin `-`, are rejected. Stdout is reserved for MCP. Stdin EOF ends the server but leaves daemon sessions alive; close them explicitly. Disconnection does not guarantee cancellation of UI actions. HTTP transport and cancellation are unsupported.

<a id="skills"></a>
## Bundled Skills distribution and format

`skills list` sorts by name; `get` returns full frontmatter-bearing content in the requested order. `--all` selects all non-hidden Skills alphabetically and takes precedence over explicit names. `--full` adds text directly under `references/` and `templates/`, without recursive discovery or execution. Empty names or frontmatter not delimited by standalone `---` lines are excluded. LF and CRLF are accepted.

`core` and `simulator-verify` are the usual bundle entries. The `marionette-agent` introduction stub is hidden but can be retrieved explicitly with get/path. An existing `MARIONETTE_AGENT_SKILLS_DIR` directory replaces bundled discovery; unset or nonexistent paths fall back to the bundle.

Skills JSON differs from the regular CLI envelope.

```json
{"success":true,"data":[{"name":"core","content":"..."}]}
```

List data contains name/description objects; get contains name/content objects. Full adds `files:[{path,content}]` when supplemental files exist. Path returns `{paths:[...]}`, named path returns `{name,path}`, and help returns `{help}`. Success exits 0; unknown names, arguments, invalid config, discovery failure, and timeout exit 1 with `{success:false,error:"..."}`. Text failures use stderr only. There is no session/schemaVersion/outcome envelope, and restore/policy app processing is not run.

Install/upgrade AOT-compiles local source and installs an adjacent dedicated `.marionette-agent-*` bundle. Failed new installations clean up the new bundle and retain the existing executable. Upgrade keeps the old bundle for old running processes; remove it only after it is no longer needed. Use `skills path` to inspect the active location.

<a id="capture"></a>
## Image acquisition and persistence

Screenshots default to ios-simulator and require `--device <UDID>`. The bundled XCTest runner recovers PNG from XCUIScreen.main.screenshot(); capture metadata includes method:xcuiscreen, display:main, mask:system-default, identity and dimensions. Allow time for first build/start with e.g. `--timeout 120000`. No connection is needed. Marionette still capture, crop and ref annotation are removed; physical-device source is unsupported. See the [acquisition contract](SPEC.md#native-ios-screenshots). MCP/workflow require device too, and image diff shares this XCUIScreen route.

Start with the [capture guide](https://r0227n.github.io/marionette_agent/en/guides/capture/). An explicit path bypasses `--screenshot-dir` inspection. Directory-based names use `screen-<32 hex digits>.png` or `.jpg`; omitting both uses `screen.png` or `screen.jpg` in a private temporary directory. Multiple images add `-1`, `-2`, etc. before the extension.

Accepted extensions are `.png` for PNG and `.jpg/.jpeg` for JPEG, case-insensitive while preserving spelling. Missing extensions are appended for the selected format. The extension does not infer the format. JPEG quality defaults to 90; 0 maps to encoder quality 1, and 100 is still lossy. PNG retains original bytes, dimensions, and transparency. JPEG retains dimensions and composites transparency onto white.

Parent directories must exist. A symlink at the specified directory itself is rejected; ancestor symlinks are allowed. All images are validated/converted and all destinations reserved exclusively before writing. Existing files, directories, and symlinks are never overwritten. The deadline includes capture, conversion, and persistence. Failures attempt to remove created images; OS deletion refusal and immediate cancellation of active I/O cannot be guaranteed. Failures never return successful paths.

<a id="recording"></a>
<a id="web-recording"></a>
## Recording lifetime and targeting

The [native recording contract](SPEC.md#device-screen-recording) defines platform APIs, target syntax, formats, sampling intervals, startup deadlines, ownership and recovery. `--platform flutter` is removed. Android uses a private pairing file, Web an explicit Chromium page endpoint; both differ from the former target syntax. Web records the viewport to MP4 and does not require macOS display permission. See the [capture guide](https://r0227n.github.io/marionette_agent/en/guides/capture/) for commands and setup.
