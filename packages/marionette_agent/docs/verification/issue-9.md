# Issue #9 doctor verification

Owner: sole Issue #9 worker. Branch: `feature/issue-9-doctor`.
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b`.
Progress index: [todo.md](../../../../todo.md).

## Automated acceptance

Commands run from `packages/marionette_agent`:

```sh
dart format .
dart analyze
dart test
```

Results: pending final run. `test/doctor_test.dart` covers sessionless parsing,
absent runtime/no implicit VM probe, SDK/path/owner failures, passive Unix IPC
compatible/mismatch/unresponsive, secret redaction in text/JSON, exhausted deadline,
and real WebSocket VM fixtures with observed/unobserved binding and connection closure.
Fixtures do not boot any app or Simulator.

## Deferred Simulator Plan

Coordinator explicitly deferred Simulator work and publication during this phase.
Reserved UDID: `FD418F17-7B55-456F-BC05-BF95BC08866F` (iPad Pro 11-inch M5, iOS 26.2).
Preflight on 2026-09-12 observed Shutdown using `xcrun simctl list devices available`.
No runtime/app runner/device has been started by this worker.

1. Re-read simulator-verify instructions; re-check the reserved UDID is Shutdown.
   If unexpectedly Booted, report and wait. Create private `mktemp -d /tmp/mra-i9.XXXXXX`,
   use session `p1-issue-9`, and record exact runtime/runner/bundle ownership in worker status.
2. Run product CLI doctor in text and JSON with the private runtime still absent or empty.
   Expect no daemon/socket/session creation; host/dependencies/Simulator checks observable,
   probe skipped. Capture sanitized responses and process exit values.
3. Boot only the reserved device, build/run this worktree's `example/` with its own runner
   and private URI file. Record runner handle and bundle ID; keep raw runner logs private.
4. Run `dart run bin/marionette_agent.dart --session p1-issue-9 connect "$VM_URI"`,
   then snapshot/session show and a product screenshot. Record ref and current UI state.
5. Run doctor with and without `--probe-uri "$VM_URI"` in text/JSON; expect compatible
   daemon, successful VM protocol observation, actual binding version/registered extensions.
   Run session show and tap the saved ref afterwards to prove the connection/ref survived.
   Observe the expected UI change with snapshot and product screenshot; inspect actual images
   with view_image and record expected versus actual screen state.
6. Repeat explicit probe with a refused loopback endpoint and a silent fixture endpoint;
   expect failure and unknown respectively, exit1, no secret values. Check saved connection
   and fresh ref remain usable after both. A reachable VM without binding is covered by
   automated wire fixture; report unknown instead of inferring capabilities.
7. Capture meaningful before/after images and sanitized text/JSON responses with commands,
   expected/actual states, actual commits, device/runtime/CLI versions and evidence paths.
8. Close only `p1-issue-9`, stop the owned runner, shut down the reserved device, and record
   teardown before release. Verify all required checks and images before draft publication.
9. Re-check remote PRs in all states and branch head, commit/push as authorized, then create
   one develop-target Draft PR with attachments and the unchecked human steps below.

## Human Handoff

- [ ] On macOS run doctor in text/JSON without a daemon; review each nextStep and exit code.
- [ ] Probe the example app explicitly, verify observed binding fields, and confirm existing
  session/ref still operates and screen changes as expected.
- [ ] Inspect attached screenshots and sanitized failure/timeout responses.

Current limitation: Simulator acceptance, image inspection, verified commit and Draft PR
are pending coordinator capacity. This is a phase handoff, not Issue completion.
