# Issue #7: opt-in debug diagnostics

Owner: worker-7, requested model gpt-6-astra / medium.
Issue: https://github.com/r0227n/marionette_agent/issues/7
Branch: `feature/issue-7-debug-diagnostics`
Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-7-debug-diagnostics`
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b`.

## Progress and acceptance

No todo.md existed at implementation start. Root `todo.md` now points here.
The initial coordinator pause was released before live verification on 2026-09-12. Final results below supersede the historical plan.

| Acceptance | Implementation / verification |
| --- | --- |
| Common --debug before/after commands | CommonOptions single source; all command grammars, help/version, workflow and record parser tests |
| Request ID, session, stage, elapsed, normalized code | DebugDiagnostics enum and metadata allowlist; CLI, IPC client, daemon and session instrumentation |
| Opt-in and concurrent isolation | Request.debug boolean; protocol version 5; existing request Zone collector; diagnostics and concurrent IPC tests |
| Single JSON stdout envelope | Existing renderer retained; IPC process tests jsonDecode the entire stdout for success and errors |
| No URI/input/app text/stack trace | No params or error messages accepted by debug events; successful fill, capability failure, timeout, parser failure, and concurrent authenticated-URI tests |
| Docs/help/progress | SPEC, ARCHITECTURE, Japanese CLI reference, generated help and root todo.md |
| Simulator acceptance | Passed text/JSON scenarios and image inspection; final results below |

## Automated checks

Working directory: `packages/marionette_agent`.
`dart format .`: passed. `dart analyze`: passed, no issues.
Initial focused run: `dart test test/protocol_test.dart test/safety_options_test.dart test/diagnostic_logging_test.dart test/ipc_test.dart`, 26 passed.
Final serial suite: 168 passed, exit 0 (1m51s). Command: `dart test --concurrency=1 --file-reporter=json:/private/tmp/mra-p1-20260912/worker-7-final-tests.jsonl`.
Verified code commit: `bb33f2e6f70189abaa3baa342fc9cd3d08b5d171`; subsequent changes are verification documentation only.
Dart 3.13.2 / Flutter 3.47.2 / macOS arm64. The final commands used the SDK's `bin/cache/dart-sdk/bin/dart` directly to avoid shared Flutter wrapper cache writes. Incidental baseline formatting in artifact_writer_test.dart was excluded from this issue's diff.
Initial parallel tests hit two existing timing-sensitive tests; serial tests passed without changing deadlines. A new test's displayed-text selector was corrected to the fixture key. The interrupted intermediate run is not counted as final verification.

## Initial resource plan (historical)

- Only allowed UDID: `E27B01A5-DA29-4953-B973-C8B8258675FB`.
- Initial state: Shutdown, reported by coordinator; independently recheck immediately before first boot after resume. If unexpectedly Booted, report and wait.
- Product session: `p1-issue-7`. Runtime: not allocated yet; use `mktemp -d /tmp/mra-i7.XXXXXX` with `umask 077` after resume.
- Keep URI and raw runner log private, outside selected attachment directory. Record runner handle, bundle ID, private runtime and device transitions in worker-7-status.json.
- Reservation remains allocated. No resources are marked released at this phase boundary.

## Simulator plan (executed with reconnect/close corrections below)

1. Confirm branch/commit and reserved UDID is Shutdown, then boot only that UDID. In this worktree's `example/`, run `flutter pub get` if needed and `flutter run -d E27B01A5-DA29-4953-B973-C8B8258675FB --debug --no-pub --vmservice-out-file=<private-runtime>/vmservice.uri`. Capture raw runner output privately; never copy it into evidence.
2. Set `MARIONETTE_AGENT_RUNTIME_DIR` to the private runtime's `runtime` child, and use the absolute worktree `packages/marionette_agent/bin/marionette_agent.dart` for every product CLI call. Read the URI file without shell tracing; pass it to `connect` without printing it.
3. For both text and JSON, execute `--session p1-issue-7 --debug connect <private URI>`, `snapshot --debug`, `tap --key tap_button --debug`, then `snapshot --debug`. Expected: connection succeeds, initial Tap count 0 becomes 1 (then 2 for second mode), stderr stages share each call's request ID and contain numeric elapsedMs with final code=OK. JSON stdout must decode as exactly one existing envelope.
4. Capture before/after using product `screenshot <absolute-evidence-path>`. Open every image with view_image and compare visible Tap count with snapshots. Record expected and actual screen/state, commands, exit codes, sanitized diagnostics, and each image's purpose.
5. Fill `--key text_input` with a synthetic secret sentinel under debug. Expected: fill succeeds and snapshot/visible length confirms the edit; stderr contains neither sentinel, selector value, app display strings, nor authenticated URI. Keep any evidence containing the sentinel private or remove it before selecting attachments.
6. After close, try connect to `http://127.0.0.1:1/issue7-private-token` in both modes. Expected: normalized connection error, no authentication/path token in stderr, and no app state change. Record actual normalized code rather than assuming backend classification.
7. Reconnect to the running fixture and execute `wait --key issue7_missing_target --timeout 1000 --debug` in both modes. Expected: TIMEOUT / exit 5, final stderr code=TIMEOUT, one JSON envelope in JSON mode, unchanged Tap count. Capture/review screen after timeout. Never resend an unknown mutation.
8. Check opt-out snapshot has no marionette_agent.debug records. Automated tests cover simultaneous independent sessions without using another Simulator; a concurrent product `session show`/`snapshot` pair can additionally check per-request IDs on the single assigned session.
9. Stop owned recording if any, close owned session, confirm daemon metadata/socket removal, quit runner, terminate owned app if necessary, and shutdown assigned UDID. Verify process/device cleanup before marking released. Keep reviewed evidence for Draft PR attachment.

## Human handoff (pending)

- [ ] Human verification: start this branch's example from a reset state, acquire a fresh private URI, repeat connect/snapshot/tap and failure/timeout in text and JSON, and compare screen and stderr with the recorded expectations.
- [x] Agent Simulator verification and actual image inspection.
- [ ] Develop-target Draft PR publication (URL and attachment verification tracked in worker result file).

Before publication, recheck all remote PR states and branch ancestry, then use the pr-create template and verify the resulting Draft PR head/base/body/attachments. No PR exists as of the implementation-phase remote check.

## Final live results

Device: iPad Pro 13-inch (M5), iOS 26.2, assigned UDID above. Only this worktree's example was built; marionette_flutter 0.6.0; bundle com.example.example. Private directory `/tmp/mra-i7.ub5Qub`, runtime child `runtime`, session `p1-issue-7`. Xcode build completed in 13.1s.

Runner command in example/: `flutter run -d E27B01A5-DA29-4953-B973-C8B8258675FB --debug --no-pub --vmservice-out-file=/tmp/mra-i7.ub5Qub/vmservice.uri`. Raw output stayed private in runner.log. Every CLI call used this worktree's absolute Dart entrypoint and explicit runtime environment.

41 recorded live calls passed. [Selected exact sanitized stdout/stderr and arguments](issue-7-cli-evidence.json) are committed. Complete local record: `/tmp/mra-i7.ub5Qub/evidence/results.json`; private harness: `/tmp/mra-i7.ub5Qub/verify.rb`. Whole JSON stdout was parsed as one object with the existing six envelope keys. Every debug response had one request ID, numeric timing and a final normalized code. Actual authentication token and input sentinel were absent from stderr and public evidence.

| Scenario, in both text and JSON | Expected and actual |
| --- | --- |
| connect with --debug before command | Success; JSON 1100ms, text 1095ms; startup, dispatch and code=OK |
| snapshot, tap --key tap_button, snapshot with --debug after command | JSON counter 0 to 1, tap 116ms; text 1 to 2, tap 94ms; snapshots and images agree |
| fill --key text_input with synthetic private input | Exit 0; separate follow-up snapshots confirmed 20 characters in both modes; cleared to 0 |
| wait --key issue7_missing_target --timeout 1000 --debug | TIMEOUT/exit 5; JSON 1008ms, text 1007ms; daemonResult and cliResult codes match |
| Reconnect and observe after timeout | Counter unchanged at 1 / 2; no mutation replay |
| Close and connect to unreachable loopback URI | CONNECTION_LOST/exit 3; JSON 1131ms, text 1096ms; no URI disclosure |
| Concurrent snapshot and secret-bearing unsupported identifier fill | Separate request IDs; snapshot exit 0 and UNSUPPORTED_CAPABILITY/exit 6; secret-free stderr |
| Snapshot without --debug | No marionette_agent.debug records; normal response retained |

Timeout retires the backend under the existing contract: the harness first observed NOT_CONNECTED, then explicitly reconnected before checking state. Changing URI after intentionally failed connect requires close: the harness first observed SESSION_CONFLICT, then explicitly closed. No product change or mutation retry was needed.

Actual timeout JSON stderr for request 80448-1513217936 / session p1-issue-7 included `daemonResult elapsedMs=956 code=TIMEOUT`, then `cliResult elapsedMs=1008 code=TIMEOUT`. The normal INFO disconnect message remained present. Diagnostics contained no URI, input, selector value, app text or stack.

## Inspected images

All six product CLI screenshots under `/tmp/mra-i7.ub5Qub/evidence/` were opened with view_image. All show empty input and the expected fixture, with no secret values. Attach all six to the Draft PR.

| Image | Actual screen |
| --- | --- |
| before-json.png | Tap count 0, Not edited |
| after-json.png | Tap count 1, Not edited |
| timeout-json.png | Tap count 1, 0 characters after clear and timeout |
| before-text.png | Tap count 1, 0 characters |
| after-text.png | Tap count 2, 0 characters |
| timeout-text.png | Tap count 2, 0 characters after clear and timeout |

## Teardown and handoff

Final close exited 0; daemon socket and metadata were confirmed absent. Runner handle 32328 received q and exited 0. Owned runner/CLI process search was empty. Assigned device was independently confirmed Shutdown at 2026-09-12 11:27 JST; reservation released only after these checks. No recording was started. The private URI file is removed after the evidence audit; raw runner logs are not attachments.

For human reproduction, start this branch's example from reset state with a fresh private URI and runtime, repeat the plan's commands in both modes, explicitly reconnect after timeout and close before changing URI. Expect counter 0, 1, 2, unchanged after timeout, and the codes above. Clear input, close, quit the runner, then shutdown the owned device.
No unresolved implementation or agent verification items; human verification remains pending.
