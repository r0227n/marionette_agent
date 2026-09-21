# Runtime verification

[日本語](ja/runtime-verification.ja.md) · [Documentation index](README.md)

[all-actions.yaml](../samples/workflows/all-actions.yaml) exercises all six workflow v1 actions in 16 steps: navigation to About and back, tap, fill, PageView swipe, scroll, wait, and snapshot. Its target is the repository's [example app](../example/README.md).

Workflow v1 does not include connection, get, images, logs, or recording actions. [all_commands_smoke.dart](../integration_test/all_commands_smoke.dart) executes those through separate product CLI processes and also validates and runs the YAML workflow. The iOS and Android scenarios are the same except for the device and recording platform.

## Preparation

Use macOS, the repository's Flutter/Dart versions, Xcode for iOS Simulator, and the Android SDK, adb, and a bootable AVD for Android. The CLI doctor checks the macOS host and iOS Simulators, so this scenario requires Xcode even for Android verification. The scenario checks Android startup and actual operations separately.

Resolve the CLI, util, and example dependencies together from the repository root:

```sh
flutter pub get
flutter devices
xcrun simctl list devices available
adb devices -l
```

Select unused iOS and Android devices and boot them. Do not share another task's device or session. If a device must be shared, serialize the entire interval from app launch through operations, recording, CLI shutdown, and app shutdown.

The following starts at the repository root. Replace `MRA_DEVICE` with the actual device ID and repeat separately for iOS and Android.

```sh
umask 077
MRA_ROOT="$PWD"
MRA_RUN=$(mktemp -d /tmp/mra-all.XXXXXX)
mkdir -m 700 "$MRA_RUN/private" "$MRA_RUN/evidence"
MRA_PLATFORM=ios
MRA_DEVICE='<iOS Simulator UDID>'
# For Android:
# MRA_PLATFORM=android
# MRA_DEVICE=emulator-5580

cd "$MRA_ROOT/example"
flutter run -d "$MRA_DEVICE" --debug --no-pub \
  --vmservice-out-file="$MRA_RUN/private/vm-uri" \
  > "$MRA_RUN/private/flutter.log" 2>&1
```

Keep the Flutter runner alive in this terminal. In a second terminal, carry over `MRA_ROOT`, `MRA_RUN`, `MRA_PLATFORM`, and `MRA_DEVICE`. Once the URI file exists, run:

```sh
cd "$MRA_ROOT"
MARIONETTE_TEST_PLATFORM="$MRA_PLATFORM" \
MARIONETTE_TEST_DEVICE="$MRA_DEVICE" \
MARIONETTE_TEST_VM_URI_FILE="$MRA_RUN/private/vm-uri" \
MARIONETTE_TEST_EVIDENCE="$MRA_RUN/evidence" \
dart run integration_test/all_commands_smoke.dart
```

Do not publish the URI or raw Flutter logs, and do not enable shell tracing. The initial Tap count must be 0. For another run, quit the previous runner with `q`, launch the app afresh, and obtain its new URI. Do not automatically resend failed operations or workflows.

## Acceptance checks

“All commands” means the current CLI commands and subcommands. It does not mean every option combination, device or OS version, or macOS/Web recording coverage.

| Command | Expected result |
| --- | --- |
| `--help` / `--version` | JSON response and exit 0 |
| `doctor` / `doctor --probe-uri` | Exit 0 and a successful independent app probe |
| `connect` | First connection and reconnection to the same URI succeed |
| `session list` / `session show` | Zero sessions initially, then one session and successful status inspection |
| `snapshot` | Initial counter 0, real refs, and one item with a key filter |
| `get text/box/count` | Expected post-action text, logical bounds, matching counts, and zero for missing targets |
| `is visible` | The tap button is known and visible |
| `tap` | One increment each through a ref and the bounds center; selector-based tab navigation |
| `fill` | Replace with 16 then 3 characters, clear, and fill again |
| `swipe` | Page 1→2 through a left gesture, then 2→1 through coordinates spanning 80% of the view |
| `scroll` | Two upward gestures of 400px and 150px reach Bottom reached |
| `wait` | Page/screen existence and About disappearance after navigating to Controls |
| `screenshot` | Decodable PNG, JPEG, and annotated PNG; visually inspect content and annotation positions |
| `logs` | Add log entry produces `manual log entry added` |
| `workflow schema` | Whole schema and each of the six action schemas |
| `workflow validate` | Validate the 16-step all-actions.yaml with input binding |
| `workflow run` | All 16 steps complete, Bottom reached, finalSnapshot refs work in a separate CLI, total counter 3 |
| `record start/status/stop` | Active recording, finalized MP4, and repeat stop returns the same artifact; visually inspect the video |
| `close` / `close --all` | Reconnect after normal close, zero sessions after close-all, not-connected errors, and no daemon socket/metadata |

Error checks compare exit and normalized error codes: disconnected is 3/NOT_CONNECTED, expired refs are 4/STALE_REF, missing targets are 4/TARGET_NOT_FOUND, and ambiguous targets are 4/AMBIGUOUS_TARGET. Binding 0.6.0 identifier operations should return 6/UNSUPPORTED_CAPABILITY. Rejected taps must not increment the counter.

## Evidence and cleanup

Every run creates a dedicated runtime and an `<evidence>/<platform>-<unique>/` directory. `results.json` records commands, expected/actual exits, redacted responses and diagnostics, state assertions, and failure reasons. On failure, the script still attempts to close its runtime's sessions and save results, then exits 1. The runtime is retained for diagnosis.

Screenshots cover initial, initial-annotated, initial-jpeg, filled-page-two, scrolled, workflow-bottom, and about states. `operations.mp4` covers UI operations and the workflow. Script PASS means CLI and state assertions passed. Open the images and play or decode the video into chronological frames to inspect input, Page 2, scrolling, tab transitions, and annotation positions. The report's `visualReview` records that this additional check is still required.

Quit the Flutter runner with `q` and stop only devices started for this run. Confirm that owned recording, session, daemon, runner, and app have stopped before removing the URI and releasing the device.

```sh
rm "$MRA_RUN/private/vm-uri"
# Stop only devices started for this run:
# xcrun simctl shutdown "$MRA_DEVICE"  # iOS
# adb -s "$MRA_DEVICE" emu kill       # Android
```

Include results and image/video evidence in the PR, together with the verified commit, environment, expected and actual outcomes, and reproducible human steps.
