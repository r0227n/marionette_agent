---
title: Start headless apps manually
description: Own an iOS device set or Android, macOS, and Web runner, then connect, record, and clean up.
---

For managed startup, use `launch` from the [headless guide](/marionette_agent/en/guides/headless/). This supplement covers starting runners yourself and attaching with `connect`. Closing the CLI connection does not terminate manually started apps.

<a id="preparation"></a>

## Shared preparation

Prepare a macOS host and the selected platform’s SDK/device. Existing measurements used the [example](https://github.com/r0227n/marionette_agent/blob/develop/example) with Flutter 3.47.2 and Marionette 0.6.0. Start each runner in a separate terminal from `example/`. Set MRA_HEADLESS_ROOT to the same path in each terminal after creating it below.

```sh
umask 077
MRA_HEADLESS_ROOT=$(mktemp -d /tmp/mra-headless.XXXXXX)
chmod 700 "$MRA_HEADLESS_ROOT"
flutter pub get
```

Store authenticated URIs and logs in this private directory. Parallel runs need separate runtimes, sessions, devices, and output paths without concurrent builds in the same checkout. Flutter recording requires ffmpeg (PNG/libx264/concat/setts), space for temporary PNGs, and conversion time at stop. Keep the host awake.

<a id="ios"></a>

## Dedicated iOS device set

Select installed identifiers from `xcrun simctl list devicetypes` and `xcrun simctl list runtimes`, then replace the two variables below. Use a dedicated set because Simulator.app may display devices in the default set.

```sh
MRA_DEVICE_TYPE='REPLACE_WITH_INSTALLED_DEVICE_TYPE'
MRA_IOS_RUNTIME='REPLACE_WITH_INSTALLED_IOS_RUNTIME'
flutter build ios --simulator --debug --no-pub
mkdir -m 700 "$MRA_HEADLESS_ROOT/ios-devices"
MRA_IOS_UDID=$(xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" create MRA-Headless \
  "$MRA_DEVICE_TYPE" "$MRA_IOS_RUNTIME")
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" boot "$MRA_IOS_UDID"
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" bootstatus "$MRA_IOS_UDID" -b
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" install "$MRA_IOS_UDID" build/ios/iphonesimulator/Runner.app
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" launch "$MRA_IOS_UDID" \
  com.example.example --enable-dart-profiling --enable-checked-mode --verify-entry-points
```

This bundle ID and app path belong to the example; substitute your own app’s values. The dedicated set does not appear in ordinary flutter devices discovery, so use simctl. Do not open that set in Simulator.app. Confirm an actual VM Service connection rather than relying only on bootstatus completion.

```sh
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" spawn "$MRA_IOS_UDID" \
  log show --last 2m --style compact \
  --predicate 'process == "Runner" AND eventMessage CONTAINS "Dart VM service is listening"' \
  > "$MRA_HEADLESS_ROOT/ios-console.log" 2>&1
python3 - "$MRA_HEADLESS_ROOT" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
match = re.search(r'Dart VM service is listening on (http://[^\s]+)',
                  (root / 'ios-console.log').read_text())
if match is None:
    raise SystemExit('VM Service is not ready; check the private app log')
(root / 'ios-uri').write_text(match.group(1))
(root / 'ios-uri').chmod(0o600)
PY
```

<a id="other-platforms"></a>

## Android, Web, and macOS

On Android, choose an AVD from `emulator -list-avds` and an unused even port. Replace the placeholder with the environment you own.

```sh
emulator -avd YOUR_AVD -port 5586 -no-window -no-audio -no-snapshot-save -read-only
```

In a separate terminal, wait until `adb -s emulator-5586 shell getprop sys.boot_completed` returns 1 before starting Flutter.

```sh
flutter run -d emulator-5586 --debug --no-pub \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/android-uri"
```

Web uses the headless Chrome runner.

```sh
flutter run -d chrome --debug --no-pub --web-run-headless \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/web-uri"
```

macOS requires both the native environment variable and the Dart define.

```sh
MARIONETTE_HEADLESS=1 flutter run -d macos --debug --no-pub \
  --dart-define=MARIONETTE_HEADLESS=true \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/macos-uri"
```

The example’s MainFlutterWindow hides NSWindow and explicitly starts FlutterEngine; enableHeadlessRendering() on the Dart side keeps rendering alive. Other apps need equivalent implementation. A logged-in GUI session and WindowServer are required; Flutter may warn about failing to foreground the hidden window.

<a id="verification"></a>

## Connect and verify

With the CLI installed, run the following for iOS. Substitute the URI file and session name for other platforms.

```sh
mkdir -m 700 "$MRA_HEADLESS_ROOT/runtime-ios"
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_HEADLESS_ROOT/runtime-ios"
marionette-agent --session manual-ios connect "$(cat "$MRA_HEADLESS_ROOT/ios-uri")"
marionette-agent --session manual-ios snapshot
marionette-agent --session manual-ios record start "$MRA_HEADLESS_ROOT/ios.mp4" --platform flutter
marionette-agent --session manual-ios tap --key tap_button
marionette-agent --session manual-ios fill --key text_input 'headless demo'
marionette-agent --session manual-ios snapshot
marionette-agent --session manual-ios screenshot "$MRA_HEADLESS_ROOT/ios-after.png"
marionette-agent --session manual-ios --timeout 60000 record stop
marionette-agent --session manual-ios close
```

Compare counter and input changes in the video and screenshot. Recording covers one Flutter view, excluding OS keyboards/dialogs. See [recording details](https://github.com/r0227n/marionette_agent/blob/develop/docs/cli-reference.md#recording) for fps, VFR, deadlines, and recovery.

For an automated smoke check, use [integration_test/record_smoke.dart](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent/integration_test/record_smoke.dart) from the CLI package. Set `MARIONETTE_RECORD_PLATFORM=flutter`, `MARIONETTE_TEST_VM_URI_FILE`, and a new `MARIONETTE_RECORD_EVIDENCE` output path each time. Existing Android verification used `MARIONETTE_RECORD_FPS=2`. These instructions are not evidence that a new run has been performed.

<a id="cleanup"></a>

## Clean up owned resources

After closing the CLI connection, send `q` to each Flutter runner. Shut down and delete only the dedicated iOS device:

```sh
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" shutdown "$MRA_IOS_UDID"
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" delete "$MRA_IOS_UDID"
```

Stop Android with `adb -s emulator-5586 emu kill` using the port from this run. Leave shared Simulators and the adb server running. Remove unneeded URI/log files and retain verified video/results. See the [headless guide](/marionette_agent/en/guides/headless/) for the tester viewport and managed-launch limitations.
