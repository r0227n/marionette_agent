# Issue #11: annotated screenshot

Issue: https://github.com/r0227n/marionette_agent/issues/11
Owner: sole worker, gpt-6-astra with medium reasoning.
Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-11-annotated-screenshot`
Branch: `feature/issue-11-annotated-screenshot`
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`).
Verified code commit: `4bb12cc1549b81673d1ad21d8bae0b52b53fab99`.
Status: required automated and Simulator verification passed; resources released.
Publication follow-up changes only verification documents and transcripts.
Draft PR: https://github.com/r0227n/marionette_agent/pull/32 (develop target).
Read-back confirmed Draft status, all 9 image attachments and pending human verification.

## Research and support boundary

Read the resolved pub-cache sources for `marionette_mcp: 0.6.0` and
`marionette_flutter: 0.6.0`, not a neighboring checkout. The connector's
`takeScreenshots` calls the fixed extension. `ScreenshotService._takeImage`
renders each RenderView layer at FlutterView.physicalSize (ceil dimensions),
optionally resizes with maxScreenshotSize using floor dimensions, and removes
failed views from the returned list. The response has PNG strings only.
Element inspection uses RenderBox.localToGlobal(Offset.zero) and logical size.
Thus neither index-to-view matching nor scale/orientation can be inferred safely.

The implemented capability is an opt-in, fixed-name debug provider in example,
not general fixed-binding support. It captures a single view with its explicit
logical/physical dimensions, view identity and zero relative rotation in the
same response. The adapter validates geometry v1; the CLI checks actual PNG
dimensions before applying the declared mapping. Multiple views/images,
unknown geometry and relative rotation are unsupported. Portrait/landscape
use current view dimensions. No overlay or upstream source modification is used.
General binding support requires equivalent upstream per-image view identity,
logical viewport/origin, physical output dimensions and transform/capture
consistency metadata; existing 0.6.0 alone is insufficient.

SPEC's exclusion of custom extensions now explicitly excludes arbitrary
extension invocation from the CLI while permitting this one backend capability.
The provider is enabled in example debug builds and can be disabled using
`--dart-define=DISABLE_MAPPED_SCREENSHOT=true` for negative verification.

## Automated verification

Working directory: `packages/marionette_agent`.

- `dart format .`: passed (72 Dart files); clean at the verified commit.
- `dart analyze`: no issues.
- Focused annotation tests: 12 passed; adapter tests: 6 passed.
- Interrupted parallel full run hit the existing 3-second FIFO startup assertion.
- Serial runs under concurrent workers also hit existing subprocess timeouts.
  Narrowed image imports to PNG/drawing and replaced the general font loader with
  a fixed ref bitmap alphabet. No product deadline or test assertion was changed.
- Final `dart test --concurrency=1 --reporter expanded`: **176 passed**, 78 seconds,
  after the observed concurrent batch Dart processes had exited. Log:
  `/private/tmp/mra-p1-20260912/issue-11-automated/dart-test-quiet.log`.
- `example`: `dart format lib`, `flutter analyze` (no issues), and `flutter test`
  (**5 passed**) on the final provider code.

Fixtures cover 1x/2x/2.5x scale, landscape dimensions, rotated/unknown geometry,
PNG dimension mismatch, multiple images, missing/out-of-range bounds, stale refs
before/during capture, ref preservation and exclusive saving/deadlines.
Only delivered refs from output-limited snapshots are retained for annotation.
An overlapping-bounds fixture verifies separate legible labels with pixel checks.
A generated fixture was also opened with view_image; it is not Simulator evidence.
Private logs: `/private/tmp/mra-p1-20260912/issue-11-automated/`.

## Simulator results and ownership

Only assigned UDID `365731BA-E8C3-48B3-A179-2F796646EE6D`:
iPad (A16), iOS 26.2. Rechecked Shutdown before boot at 2026-09-12 06:05 UTC.
Runtime: `/tmp/mra-i11.knkZn0/runtime`, session `p1-issue-11`.
Bundle: `com.example.example`. Raw runner logs stay private in
`/tmp/mra-i11.knkZn0/`; VM URI files were private there and removed after teardown.
Only the evidence subdirectory is public-attachment eligible.
The earlier coordinator phase gate was released before boot. Flutter 3.47.2,
marionette_flutter/marionette_mcp 0.6.0, image 4.9.1; 1640x2360 portrait PNGs.

Every live call uses this worktree's product Dart CLI, session `p1-issue-11`, and
the private runtime above. The committed smoke script checks expectations and
writes sanitized transcripts: [supported: 22 calls](issue-11-supported.json),
[provider disabled: 17 calls](issue-11-unsupported.json).

| Scenario | Expected | Actual |
| --- | --- | --- |
| Annotation before snapshot, text/JSON | STALE_REF, no file | Both exit 4; no files |
| Snapshot then annotation, text/JSON | Same refs/generation; aligned labels | Generation 2, 28 labels, zero skipped; both exit 0 |
| Original/annotated destination already exists, text/JSON | IO_ERROR; preserve bytes | All 4 calls exit 1; original unchanged |
| Tap published @e56 after annotations and IO errors | Navigate to About | Exit 0; actual screen shows Workflow fixture |
| Annotation after tap, text/JSON | STALE_REF, no file | Both exit 4; no files |
| New About snapshot then annotation | Fresh refs match actual positions | Generation 3, 4 labels, zero skipped; @e57 frames Workflow fixture |
| Use @e59 after About annotation | Return to Controls | Exit 0; actual Controls screen, Tap count: 0 |
| Provider-disabled app, text/JSON | UNSUPPORTED_CAPABILITY, no file | Both exit 6; no annotated files |
| Provider-disabled plain screenshot/ref tap | Preserve base features and refs | Original PNG saved; ref navigates to About and back |

Opened all 9 live PNGs with view_image. On Controls, @e31 frames the tap button
whose snapshot logical bounds are x=32, y=156, width=97.3416976928711, height=48;
@e34 frames the input and @e37 frames PageView. About's @e57 frames the observed
Workflow fixture text at x=354.14990234375, y=574, width=111.7001953125, height=20.
The explicit provider geometry applies the physical/logical mapping; visual
inspection confirmed these frames align with actual elements, not guessed pixels.
Text/JSON annotation PNGs have identical SHA-256:
`9c0e0f2daa92f4eb97512cd7282ba23c2d63fe23c6a8d435172851f903ec8b24`.
The original remains `4eaea9c319e9626ae4fa36a7bf0c1c9e2fe8d93a902fe233a2381db3b39b8a00`.

Live landscape rotation was not performed: Computer Use access to Simulator was
denied. No UI permission workaround was used. Landscape geometry and 90/180/270
relative-rotation rejection are fixture-tested; live support evidence is limited
to the required verified portrait configuration with the opt-in provider.

Executed launch commands from `example/` (one runner at a time):

```sh
flutter run -d 365731BA-E8C3-48B3-A179-2F796646EE6D --debug --no-pub --vmservice-out-file=/tmp/mra-i11.knkZn0/vm-uri
flutter run -d 365731BA-E8C3-48B3-A179-2F796646EE6D --debug --no-pub --dart-define=DISABLE_MAPPED_SCREENSHOT=true --vmservice-out-file=/tmp/mra-i11.knkZn0/vm-uri-unsupported
```

Both runner stdout/stderr streams were redirected to private logs outside evidence.
After each launch, executed from `packages/marionette_agent`:

```sh
MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-i11.knkZn0/vm-uri \
MARIONETTE_TEST_EVIDENCE=/tmp/mra-i11.knkZn0/evidence \
MARIONETTE_AGENT_RUNTIME_DIR=/tmp/mra-i11.knkZn0/runtime \
dart run integration_test/annotated_screenshot_smoke.dart

MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-i11.knkZn0/vm-uri-unsupported \
MARIONETTE_TEST_EVIDENCE=/tmp/mra-i11.knkZn0/evidence \
MARIONETTE_AGENT_RUNTIME_DIR=/tmp/mra-i11.knkZn0/runtime \
MARIONETTE_TEST_UNSUPPORTED=true \
dart run integration_test/annotated_screenshot_smoke.dart
```

Teardown: each script's `close` succeeded; runtime socket was removed and `lsof`
found no daemon.lock holder. Sent `q` to runner handles 61413 and 45953; both
exited 0 and logged Application finished. No recording was started.
`xcrun simctl shutdown 365731BA-E8C3-48B3-A179-2F796646EE6D` succeeded; simctl
confirmed Shutdown at 2026-09-12 06:27:20 UTC. Removed both private VM URI files.
Raw logs remain private. Device resources were released only after these checks.

## Attachment manifest

All files are under `/tmp/mra-i11.knkZn0/evidence/` and were opened:

- `portrait-original.png`: Controls before annotation.
- `portrait-annotated-true.png`: JSON command, 28 aligned refs.
- `portrait-annotated-false.png`: text command, identical 28 labels.
- `portrait-about-original.png`: actual screen after preserved ref tap.
- `portrait-about-annotated.png`: 4 refs aligned on About.
- `portrait-returned-controls.png`: actual return using preserved About ref.
- `unsupported-original.png`: ordinary capture still works without provider.
- `unsupported-about-original.png`: preserved ref still navigates without provider.
- `unsupported-returned-controls.png`: ordinary state after return.

The generated fixture is not selected as live PR evidence. The two sanitized JSON
transcripts above preserve all commands, expected outcomes, responses and diagnostics.

## Human reproduction (pending)

- [ ] Human verification not yet performed.

From this branch, launch example debug on an unused assigned Simulator, using
`flutter run -d <UDID> --debug --vmservice-out-file=<private-uri-file>`.
Create a private unique directory with `mktemp -d /tmp/mra-i11.XXXXXX`, set
`MARIONETTE_AGENT_RUNTIME_DIR` to its runtime child, and use one session consistently.
Run this worktree's `packages/marionette_agent/bin/marionette_agent.dart` with Dart.
Connect using the URI read privately from the file; do not print the URI.
Run snapshot, screenshot to original.png, and screenshot --annotate to a new PNG.
Compare @eN labels with snapshot refs and visible elements, then tap one published
ref. Repeat the negative scenarios above and finish session/runner/device teardown.
For automated reproduction, set the three MARIONETTE_* variables above to your
fresh private paths and run the committed smoke script. Quit the enabled runner
before restarting with DISABLE_MAPPED_SCREENSHOT=true, then run the script with
MARIONETTE_TEST_UNSUPPORTED=true. Each script closes its CLI session; finish the
runner with q and shut down only your assigned device. Never reuse published
evidence paths for a new run, because saves are intentionally exclusive.
