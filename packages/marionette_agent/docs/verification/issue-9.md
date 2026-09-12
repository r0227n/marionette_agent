# Issue #9 doctor verification

Owner: sole Issue #9 worker. Branch: `feature/issue-9-doctor`.
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b`.
Progress index: [todo.md](../../../../todo.md).

## Automated acceptance

Commands run from `packages/marionette_agent`:

```sh
dart format .
dart analyze
dart test --concurrency=1
```

Results: format passed; analyze reported no issues; all 179 tests passed at
`ea98d00d3ef053b1c3c6f944c6181c62c3b27082`. Full log:
`/private/tmp/mra-p1-20260912/worker-9-tests-final.log`.
The first concurrent run hit existing subprocess startup deadlines under host load;
the coordinator requested serial runs. No product deadline or existing assertion was relaxed.
`test/doctor_test.dart` covers sessionless parsing,
absent runtime/no implicit VM probe, SDK/path/owner failures, passive Unix IPC
compatible/mismatch/unresponsive, secret redaction in text/JSON, exhausted deadline,
and real WebSocket VM fixtures with observed/unobserved binding and connection closure.
`test/idle_timeout_test.dart` additionally proves repeated passive handshakes cannot
renew the daemon's idle lifetime. Actual dispatched requests still receive a full idle interval.
Fixtures do not boot any app or Simulator.

## Final Simulator Results

Verified code commit: `ea98d00d3ef053b1c3c6f944c6181c62c3b27082`.
Documentation/evidence follow-up commits do not change this code.
Date: 2026-09-12. macOS 26.5.2 (25F84), Flutter 3.47.2, Dart 3.13.2 stable,
marionette_flutter 0.6.0, marionette_mcp 0.6.0.
Reserved UDID: `FD418F17-7B55-456F-BC05-BF95BC08866F` (iPad Pro 11-inch M5, iOS 26.2).
Preflight immediately before boot observed Shutdown. Only this UDID was booted/operated.
Final private root: `/tmp/mra-i9.Xr0H4s`; runtime: `/tmp/mra-i9.Xr0H4s/runtime`;
session: `p1-issue-9`; bundle: `com.example.example`; runner tool handle: `38494`.

```sh
# In example/; URI and raw runner log remain private.
flutter pub get
flutter run -d FD418F17-7B55-456F-BC05-BF95BC08866F --debug --no-pub \
  --vmservice-out-file=/tmp/mra-i9.Xr0H4s/vm-uri
# In packages/marionette_agent/, another terminal:
MARIONETTE_TEST_PRIVATE_DIR=/tmp/mra-i9.Xr0H4s \
  dart run integration_test/doctor_smoke.dart
```

Actual: all 50 product-CLI calls passed. Every doctor scenario below ran in text and JSON.
[Sanitized commands, expected/actual exit codes and full responses](issue-9-results.json)
are committed as evidence; the harness checks raw URI/auth-path and fixture-token absence
before recording stdout/stderr. Doctor stderr was empty in every scenario.

| Scenario | Expected and actual |
| --- | --- |
| No daemon/runtime, no explicit URI | exit0; runtime/probe skipped; runtime stays absent |
| IPC incompatible protocol | failure/exit1; no command bytes sent; socket retained |
| IPC unresponsive | unknown/exit1; no command bytes sent; socket retained |
| Connected daemon, no explicit URI | exit0; compatible ready handshake, probe skipped |
| Explicit running example URI | success/exit0; VM protocol 4.21; observed binding 0.6.0 and 17 registered extensions |
| Refused explicit endpoint | failure/exit1; URI and remote error withheld |
| Silent explicit VM endpoint, timeout2500 | unknown/exit1; dedicated connection closed |
| Reachable fixture VM without binding | success/exit0; bindingStatus unknown, bindings empty |

For each explicit probe pair, session show before/after was identical, daemon metadata and
runtime entries were unchanged, and the exact pre-probe ref remained usable. Tapping refs
`@e33`, `@e93`, `@e153`, `@e213` after successful/refused/timeout/unobserved probe pairs
respectively produced Tap count 1/2/3/4. No snapshot was taken between saving each ref and
using it after the probes. All five actual images were read with view_image; the visible
counter matches snapshot state and the remaining Controls UI remains unchanged.

Evidence directory: `/tmp/mra-i9.Xr0H4s/evidence/`:
- `doctor-before.png`: Tap count 0, fresh Controls fixture.
- `doctor-after-successful.png`: Tap count 1 after saved-ref tap following successful probes.
- `doctor-after-refused.png`: Tap count 2 after saved-ref tap following refused probes.
- `doctor-after-timeout.png`: Tap count 3 after saved-ref tap following timed-out probes.
- `doctor-after-unobserved.png`: Tap count 4 after saved-ref tap following unknown-binding probes.
- `doctor-results.json`: source for the committed sanitized result record.

Teardown: harness closed its session and all local fixture sockets. Daemon metadata and
socket were absent. Runner `38494` exited0 after `q`; reserved Simulator shutdown succeeded
and simctl confirmed Shutdown. URI files from both runs were removed. Raw runner logs are
private and are not PR attachments. Earlier runner `79997` also exited0 after `q`; its
two private runtimes were closed before the final run. Worktree is preserved.

## Human Handoff

Start with a freshly launched example (Tap count0). Use a newly reserved Simulator and
a new private directory so old daemon/app state cannot affect reproduction:
confirm the reserved device is Shutdown, then run `xcrun simctl boot <YOUR_RESERVED_UDID>`.

```sh
# Repository root, terminal A
umask 077
MRA_DOCTOR_PRIVATE=$(mktemp -d /tmp/mra-i9.XXXXXX)
mkdir -m 700 "$MRA_DOCTOR_PRIVATE/evidence"
cd example
flutter pub get
flutter run -d <YOUR_RESERVED_UDID> --debug --no-pub \
  --vmservice-out-file="$MRA_DOCTOR_PRIVATE/vm-uri"
# Terminal B, packages/marionette_agent; substitute terminal A's private path.
MARIONETTE_TEST_PRIVATE_DIR=<PRIVATE_PATH> dart run integration_test/doctor_smoke.dart
```

The harness performs the full text/JSON matrix and closes its CLI session. Review the
result JSON and five screenshots; then stop runner with `q`, shut down the reserved
device, and remove the private URI file. URI values must not be pasted into public logs.

- [ ] On macOS run doctor in text/JSON without a daemon; review each nextStep and exit code.
- [ ] Probe the example app explicitly, verify observed binding fields, and confirm existing
  session/ref still operates and screen changes as expected.
- [ ] Inspect attached screenshots and sanitized failure/timeout responses.

Human verification remains pending. Agent acceptance has passed. Registered extensions
are observations, not a claim that every listed operation is supported by this CLI.
