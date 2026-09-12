# Issue #5: is visible verification

## Scope and environment

- Issue: https://github.com/r0227n/marionette_agent/issues/5
- Owner: sole Issue #5 worker; branch `feature/issue-5-is-visible`.
- Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-5-is-visible`.
- Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b`.
- Verified implementation: `0fc5785f7bd7fc2c67a60a3574f663c479142852`.
  Simulator ran the identical product code before this commit; only test timeout
  and documentation changes followed the live run.
- Flutter 3.47.2; example `marionette_flutter` 0.6.0; backend `marionette_mcp` 0.6.0.
- iPhone Air, iOS 26.2, reserved UDID `C66CFC02-289C-4106-8F63-93DF694BB2C4`.
- Private run directory `/tmp/mra-i5.3SLMDd`, runtime `/tmp/mra-i5.3SLMDd/runtime`, session `p1-issue-5`.
- Progress file `todo.md` was absent and was created at implementation start.

## Automated checks

`dart format .` and `dart analyze` passed in `packages/marionette_agent`.
Formatting-only churn in the pre-existing `artifact_writer_test.dart` was excluded.
`dart test --concurrency=1` passed all 168 tests in 1m31s on the implementation
commit above, with no skips. The default-concurrency and first serial runs hit
process startup timeouts on the shared host (load average 495.72); the final run
passed after load decreased. No product code or existing test deadline was changed
to resolve those failures. Log: `/private/tmp/mra-p1-20260912/worker-5-tests-final.log`.
Unit and IPC fixtures cover true/false/null, missing/ambiguous targets, unsupported
selectors and stale refs. Unit tests verify the exact published observation is
retained, no mutation is sent, and the prior ref still works for a later tap.

## Simulator commands and results

The example was launched from this worktree with:

```sh
flutter run -d C66CFC02-289C-4106-8F63-93DF694BB2C4 --debug --no-pub \
  --vmservice-out-file=/tmp/mra-i5.3SLMDd/vmservice.uri
```

All product CLI calls used `dart packages/marionette_agent/bin/marionette_agent.dart`,
`--session p1-issue-5` and the private `MARIONETTE_AGENT_RUNTIME_DIR` above.
The URI was read privately from the runner output file for `connect`; neither the
URI nor raw runner log is public evidence.

| Command (both text and `--json` where indicated) | Expected | Actual |
| --- | --- | --- |
| `snapshot --json` | Tap control visible, initial fixture state | generation 1, tap_button ref @e3, visible true, Tap count: 0 |
| `screenshot .../evidence/before.png` | Visible Tap me control, initial state | Image opened and matched snapshot |
| `is visible --key tap_button` (both) | Known true | `Visible: true`; data `{"known":true,"value":true}`, exit 0 |
| `is visible @e3` (both) | Same ref remains valid | Same true results, exit 0 |
| `is visible --key missing_issue_5` (both) | Missing target error | TARGET_NOT_FOUND, exit 4 |
| `is visible --type Text` (both) | Ambiguity error | AMBIGUOUS_TARGET, exit 4 |
| `is visible --identifier tap_button` (both) | Unsupported selector | UNSUPPORTED_CAPABILITY, exit 6 |
| `screenshot .../evidence/after.png` | No UI change | Image opened: Tap count 0, Not edited, Page 1 unchanged |
| `snapshot --json` | Same state, next generation | Element data excluding refs exactly matched before snapshot |
| `is visible @e3` (both, after new snapshot) | Old ref stale | STALE_REF, exit 4 |

The key and ref reads were interleaved with error cases without a new snapshot.
This verifies successful visibility reads preserve refs. All error responses were
not_sent. The shell assertions and normalized element comparison passed.

The live binding returned visible=true for all 21 observed elements. It does not
provide a false/null fixture in this screen; those values are verified with typed
FakeBackend unit and IPC fixtures, without claiming live false/null evidence.

## Evidence and teardown

- `/tmp/mra-i5.3SLMDd/evidence/before.png` and `after.png`: both opened with view_image.
  Both have SHA-256 `343f2e0af26b1f4999f0e73933fef0a06cce0a63bc734512dfa14bd28ab96f83`.
- `/tmp/mra-i5.3SLMDd/evidence/scenarios.log`: commands and exit codes.
- Same directory: `before.json`, `after-snapshot.out`, `*-text.out`, `*-json.out`.
- Harness: `/tmp/mra-i5.3SLMDd/verify.sh` (no URI).
- `close` succeeded, daemon metadata disappeared, Flutter runner session 96784
  exited 0 after `q`, and the assigned Simulator was shut down and rechecked.
- Bundle ID `com.example.example`; URI file deleted; raw runner log remains private.

## Human reproduction (pending)

1. Use this branch, run `flutter pub get` in `example`, and choose an available
   Simulator under the device ownership rules. Start from a fresh app launch.
2. Create a private short directory with `umask 077; mktemp -d /tmp/mra-i5.XXXXXX`.
   In the runner terminal, start the example with `--vmservice-out-file` pointing
   inside it. In the CLI terminal, set `MARIONETTE_AGENT_RUNTIME_DIR` to its runtime
   child, and read the URI file into a variable without printing it.
3. Connect using this worktree's Dart CLI and a private session. Run snapshot and
   substitute its actual tap_button ref for @e3 above. Repeat the command table.
4. Confirm true matches the visible button and that reads/errors leave Tap count 0,
   Not edited and Page 1 unchanged. New snapshot must make the old ref stale.
5. Close the session, stop the runner with `q`, shut down the owned Simulator and
   remove the URI file. Run unit/IPC tests to inspect false/null fixture results.

- [ ] Human has reviewed the PR and reproduced the steps.
