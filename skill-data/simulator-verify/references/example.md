# Example fixture and preparation

For marionette_agent development, use the task checkout's `example/` app. It pins
`marionette_flutter` 0.6.0 and uses Flutter 3.47.2. Its debug entrypoint initializes
MarionetteBinding and log collection. Read that checkout's `example/README.md`
for changes to its fixture. Installed CLI users can use their own debug app with
the binding initialized; this guide does not require a neighboring source repository.

## Private run setup

Run this in the checkout root, and carry these exact environment values to the
runner terminal and CLI terminal. `<UDID>` must come from the available device list
and the shared allocation record. Keep raw runner logs outside evidence.

```sh
umask 077
MRA_VERIFY_DIR=$(mktemp -d /tmp/mra-check.XXXXXX)
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_VERIFY_DIR/runtime"
export MRA_VERIFY_SESSION=verify
export MRA_VERIFY_URI_FILE="$MRA_VERIFY_DIR/uri"
mkdir -m 700 "$MRA_VERIFY_DIR/evidence"
```

In the app's `example/` directory, prepare dependencies and keep this runner alive:

```sh
flutter pub get
flutter run -d <UDID> --debug --no-pub --vmservice-out-file="$MRA_VERIFY_URI_FILE"
```

Back in the checkout root, use the task's entrypoint (installed users substitute
`marionette-agent` for `dart "$MRA_VERIFY_CLI"`):

```sh
set +x
MRA_VERIFY_CLI=bin/marionette_agent.dart
MRA_VERIFY_URI=$(cat "$MRA_VERIFY_URI_FILE")
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" connect "$MRA_VERIFY_URI"
unset MRA_VERIFY_URI
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" snapshot
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" tap --key tap_button
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" snapshot
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot "$MRA_VERIFY_DIR/evidence/after-tap.png"
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" close
```

Expected on a freshly launched fixture: `Tap count: 0` becomes `Tap count: 1`.
Compare the snapshot with the opened screenshot. Quit the runner with `q`, confirm
cleanup, and release the device in the allocation record. Restart the app to reset.

| Fixture key | Check |
| --- | --- |
| `tap_button` / `tap_result` | Tap count increases once |
| `text_input` / `fill_result` | Replacement, clear, and displayed character count |
| `page_view` / `page_result` | Left/right finger gestures change the current page |
| `dismissible_item` / `dismiss_result` | Left swipe displays Item dismissed |
| `operation_scroll_area` / `scroll_result` | Scroll to Bottom reached |
| `log_button` | A manual log entry |
| `controls_tab` / `about_tab` | Navigation; returning to Controls recreates its state |
| `advanced_tab` | Optional typed controls and interaction provider |

Read `core`'s command reference for capability-dependent behavior. Capture each
required state with a distinct filename; the CLI refuses existing destinations.
