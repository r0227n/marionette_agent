# Issue #11: annotated screenshot

Issue: https://github.com/r0227n/marionette_agent/issues/11
Owner: sole worker, gpt-6-astra with medium reasoning.
Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-11-annotated-screenshot`
Branch: `feature/issue-11-annotated-screenshot`
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`).
Status: implementation and live verification in progress; no PR published yet.

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

- `dart format .`: passed during implementation; final run pending.
- `dart analyze`: no issues during implementation; final run pending.
- Focused annotation/adapter tests: 16 passed before final label placement changes.
- Interrupted parallel full run hit the existing 3-second FIFO startup assertion.
- Serial full run found a 3-second stdin startup timeout. Narrowed annotation's
  image imports to the PNG/drawing modules, matching the existing startup boundary.
  No product deadline or test assertion was changed. Final rerun pending.
- `example`: `flutter test` passed all 5 widget tests. Final analyze pending.

Fixtures cover 1x/2x/2.5x scale, landscape dimensions, rotated/unknown geometry,
PNG dimension mismatch, multiple images, missing/out-of-range bounds, stale refs
before/during capture, ref preservation and exclusive saving/deadlines.
Private logs: `/private/tmp/mra-p1-20260912/issue-11-automated/`.

## Simulator plan and ownership

Only assigned UDID `365731BA-E8C3-48B3-A179-2F796646EE6D`:
iPad (A16), iOS 26.2. Rechecked Shutdown before boot at 2026-09-12 06:05 UTC.
Runtime: `/tmp/mra-i11.knkZn0/runtime`, session `p1-issue-11`.
Bundle: `com.example.example`. Raw runner log and VM URI remain private in
`/tmp/mra-i11.knkZn0/`; only its evidence subdirectory is public-attachment eligible.
The earlier coordinator phase gate was released before boot.

Expected scenarios, all using this worktree's product Dart entrypoint:

1. Before snapshot, annotated capture in text/JSON fails STALE_REF with no files.
2. Snapshot then original screenshot and annotated text/JSON captures succeed.
   Compare labels and frames with actual elements and snapshot bounds; read PNGs.
3. Reuse a ref after annotation for an actual tap; expected screen/state changes.
   Verify generation/ref identity did not change during annotated capture.
4. After the tap invalidates snapshot, text/JSON annotation fails STALE_REF.
5. Annotating to an existing original or annotation destination fails IO_ERROR;
   compare original bytes before/after. No output should appear on failure.
6. New snapshot on About produces labels aligned with content and navigation.
   Exercise landscape orientation if the assigned device can be rotated safely.
7. Restart the same assigned app with provider disabled: text/JSON return
   UNSUPPORTED_CAPABILITY, plain screenshot and previously published ref still work.
8. Close only this session, confirm daemon exits, quit runner, terminate owned app
   if necessary, and shutdown the assigned device before reporting released.

Actual results, verified commits, selected images and teardown will be recorded
here after executing these steps. Required live verification remains incomplete.

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
