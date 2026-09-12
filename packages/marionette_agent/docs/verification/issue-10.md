# Issue #10: snapshot filter verification

Issue: https://github.com/r0227n/marionette_agent/issues/10

Owner: sole Issue #10 worker; coordinator requested gpt-6-astra / medium.
Branch: `feature/issue-10-snapshot-filter`.
Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`).
Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-10-snapshot-filter`.
Progress index: repository-root `todo.md`, created because none existed.

## Implementation and automated checks

The command accepts zero or one exact observed-value filter. Full observation
still determines selector uniqueness and ref numbering. Only delivered refs
remain actionable. Filter metadata is emitted before output-budget metadata.
Unknown text and unsupported action identifiers remain useful observations.
Workflow v1's snapshot step grammar is unchanged.

Checks run from `packages/marionette_agent` on 2026-09-12, Dart 3.13.2 macos_arm64:

| Command | Expected | Actual |
| --- | --- | --- |
| `dart format .` | Successful formatting | Exit 0, 69 files; unrelated baseline test formatting restored to keep scope |
| `dart analyze` | No issues | Exit 0, no issues after fixing initial test/lint errors |
| `dart test test/snapshot_filter_test.dart` | All filter regressions pass | Exit 0, 6 tests passed |
| `dart test` | Entire suite passes | 166 passed, 3 failures: existing FIFO subprocess, concurrent startup, and stdin subprocess timeouts |
| `dart test --concurrency=1` | Entire suite passes | Existing workflow validation exceeded its 30s runner timeout; stdin subprocess exceeded its internal 3s wait. Private log: `/private/tmp/mra-p1-20260912/worker-10-tests.log` |
| `dart test --concurrency=1 --timeout=3x` | Diagnostic run | Interrupted by coordinator; not used as acceptance evidence |
| `dart test --concurrency=1` (resumed, original deadlines) | Entire suite passes | Exit 0, all 169 passed in 2m50s; `/private/tmp/mra-p1-20260912/worker-10-tests-resumed.log` |

The serial retry required ordinary approved escalation because the Flutter Dart
launcher attempted an SDK-cache write outside workspace-write. No product
timeouts, test assertions, or unrelated tests were modified. The 30s validation
timeout also allowed its late assertion to overlap the next test; that secondary
failure is retained in the private log rather than treated as a filter failure.

`test/snapshot_filter_test.dart` verifies all selector kinds, zero/one/multiple
matches, unchanged unfiltered schema, hidden duplicate types, unknown text,
unsupported identifier matching, complete numbering, hidden/old/omitted ref
rejection, current ref operation, invalid input preserving refs, and text/JSON
filter versus truncation metadata including empty results and content boundaries.

## Simulator procedure

The initial preparation-only phase was released by the coordinator. On resume,
`xcrun simctl list devices available --json` confirmed the reserved UDID
`5211B591-51B7-49BA-8F3F-8577EEB84659` was Shutdown before boot. Device:
iPad mini (A17 Pro), iOS 26.2. Only this device is used; builds run one at a time.
Owned bundle: `com.example.example`. Private run directory:
`/tmp/mra-i10.gDuYhj`; runtime: `/tmp/mra-i10.gDuYhj/runtime`.
Flutter 3.47.2, fixed `marionette_flutter` 0.6.0. `flutter pub get` succeeded.

For reproduction, from this worktree, create private state and record actual paths,
runner handle, bundle ID, device model/OS, and verified commit in the worker status:

```sh
umask 077
MRA_I10_DIR=$(mktemp -d /tmp/mra-i10.XXXXXX)
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I10_DIR/runtime"
MRA_I10_SESSION=p1-issue-10
MRA_I10_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
mkdir -m 700 "$MRA_I10_DIR/evidence"
```

Recheck assigned device via `xcrun simctl list devices available --json`, then boot
only the reserved UDID. From `example/`, prepare dependencies and run:

```sh
flutter run -d 5211B591-51B7-49BA-8F3F-8577EEB84659 --debug --no-pub --vmservice-out-file="$MRA_I10_DIR/uri"
```

Keep runner output private. In a separate shell, carry the same private variables
explicitly, disable shell tracing, and connect with the product Dart entrypoint:

```sh
dart "$MRA_I10_CLI" --session "$MRA_I10_SESSION" connect "$(cat "$MRA_I10_DIR/uri")"
dart "$MRA_I10_CLI" --session "$MRA_I10_SESSION" snapshot --json
dart "$MRA_I10_CLI" --session "$MRA_I10_SESSION" screenshot "$MRA_I10_DIR/evidence/before.png"
```

Run each observation scenario in both text and JSON, preserving sanitized output
with exact command, exit/error code, expected/actual response, and screen state.
Compare attributes/order with full snapshot, excluding generation/ref differences:

| Scenario / command suffix | Expected response and actual-screen check |
| --- | --- |
| `snapshot --key tap_button` | One match matching full observation; totalCount equals full count; a valid ref |
| `snapshot --text 'Tap me'` | Every exact displayed-text match from full observation; multiple is success if backend reports multiple |
| `snapshot --type Text` | Multiple matches from full observation; ref safety unchanged |
| `snapshot --identifier missing-i10` | Successful empty observation when identifier absent/unsupported; no fabricated attribute |
| `snapshot --key missing-i10` | Empty elements, matchedCount 0, new generation; screen unchanged |
| `snapshot --type Text --max-output 1` | Empty delivered elements, matchedCount > 0, truncated true, originalCount = matchedCount, omittedCount = originalCount |
| `snapshot --key missing-i10 --max-output 1` | Empty match, truncated false, originalCount/omittedCount 0 |
| `snapshot --key tap_button --max-output 10000 --content-boundaries` | Retained valid ref and distinct filter/truncation/boundary metadata |
| `snapshot --key tap_button --type Text` | INVALID_ARGUMENT, exit 2; screen/ref state unchanged |

Save a full-snapshot ref, then issue a filtered snapshot and attempt the old ref:
`tap <old-ref>` must return STALE_REF without incrementing Tap count. Obtain a
fresh `snapshot --key tap_button`, immediately `tap <returned-ref>`, then full
snapshot plus `snapshot --key tap_result`: Tap count must increase from 0 to 1.
Capture `after-valid-ref.png` with product `screenshot`; open both PNGs with
`view_image` and compare actual visible counter. A screenshot request does not
invalidate refs. Do not use old example ref numbers or retry unknown mutations.

The initial run exposed no unknown text types. A scoped `SnapshotLabel` Semantics
subclass fixture was added to example, with two different labels and no keys.
The final run explicitly requires these rows and their same-text child Text rows
to have no refs. Filtering one label hides the other duplicate type, so comparing
ref availability against the full snapshot detects unsafe filter-local uniqueness.

## Actual Simulator results

Final command, from `packages/marionette_agent`:

```sh
MARIONETTE_AGENT_RUNTIME_DIR=/tmp/mra-i10.gDuYhj/runtime \
MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-i10.gDuYhj/uri \
MARIONETTE_TEST_EVIDENCE=/tmp/mra-i10.gDuYhj/evidence/results.json \
dart run integration_test/snapshot_filter_smoke.dart
```

Exit 0, 47 records passed. The command list and full text/JSON responses are in
[issue-10-results.json](issue-10-results.json). Each filtered row was compared
against the full observation, normalizing only the newly assigned ref number;
type, attributes, order, and presence/absence of safe refs matched exactly.

| Scenario | Expected and actual |
| --- | --- |
| Full snapshot | 45 observed rows |
| key tap_button / text `Tap count: 0` | 1 match, valid ref |
| text `Filter label A` | 2 matches (SnapshotLabel and Text), neither has a ref |
| type SnapshotLabel | 2 unknown display-only rows, neither has a ref |
| identifier snapshot_label_a | 1 observed match, no ref; action identifier unsupported |
| type Text | 16 matches, same ref safety as full observation |
| Missing key / identifier | 0 matches, successful new snapshot |
| text `Tap me` | 0 matches, matching full observation; the binding omits the button caption as separate text |
| type Text + max-output 1 | matchedCount/originalCount/omittedCount 16, empty delivery, truncated true |
| Missing key + max-output 1 | matchedCount/originalCount/omittedCount 0, truncated false |
| Mixed key/type filters | INVALID_ARGUMENT, exit 2 in text and JSON |
| Old ref after new filtered snapshot | STALE_REF, exit 4 in text and JSON; counter unchanged |
| Valid visible ref from JSON then text | Both operate once; counter 0 to 1 to 2 |

All four final PNGs under `/tmp/mra-i10.gDuYhj/evidence/` were opened with
`view_image` and inspected. `before.png` and `after-stale-ref.png` show counter 0
and have identical SHA-256 `6cf67d0d4f26725a3c729119c87f02b49928e8927a213c07987913e2f6efedd2`.
`after-valid-ref.png` shows 1; `after-valid-text-ref.png` shows 2. Both labels,
untouched input, and Page 1 remain visible. These four files are the selected PR
attachments; the earlier pre-fixture run is superseded.

After the fixture change, `flutter analyze` passed with no issues and all 6
`flutter test` tests passed in example. Package `dart analyze` passed again after
the integration script was finalized. The 169-test package pass covers unchanged
production code; no test deadlines or assertions were relaxed.

## Teardown and publication gates

Close the owned session, confirm daemon exit, stop the owned runner with `q`, and
terminate only the recorded bundle on the assigned device if necessary. Shutdown
the reserved UDID and verify its state before reporting released. Remove the
private URI when no longer needed; keep selected evidence for attachment.

Before publication rerun affected checks if code changed, record verified code
commit, inspect all selected images, check remote PRs in all states and head/base,
then create one develop-target Draft with attachments. Re-read draft status,
head, body, attachments, and pending human checkbox.

- [x] Simulator response/actual-screen results and inspected evidence recorded.
- [x] Session close succeeded; daemon metadata absent; Flutter runner exited 0.
- [x] Targeted app termination found nothing running; assigned Simulator shutdown
      succeeded and was verified at 2026-09-12T15:16:52+09:00. Private URI removed.
- Draft URL, exact head and uploaded attachment URLs are recorded in the worker
  handoff and verified against the published PR body.
- [ ] Human: reset app, launch this branch on an assigned Simulator, reconnect,
      reproduce the filter/old-ref/current-ref steps, and confirm counter 0 to 1.

Human verification remains pending. Publication is performed only after the
above checks and evidence inspection; no Ready conversion or merge is authorized.
