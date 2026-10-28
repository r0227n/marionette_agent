---
title: Native dialogs and photo pickers
description: Inspect, tap, and swipe iOS Simulator and Android system UI with XCUITest and UI Automator runners.
---

Bind a native device to your session, then use the same `snapshot`, `tap`, and `swipe` commands for Flutter controls, permission dialogs, and system photo pickers. A bound session can operate without a Flutter VM connection. Connecting the VM adds Flutter observations to the same session. iOS uses XCUITest / XCUIAutomation and Android uses UI Automator through authenticated local runners. Screen capture remains a separate feature.

## Prepare a runner

Use the runner sources from the same repository revision as the CLI. Run setup commands from the repository root. You need Xcode and XcodeGen for iOS Simulator, or Android SDK 36, JDK 17 or newer, and an online emulator for Android. Set `JAVA_HOME` and `ANDROID_HOME` for the Android build. No Computer-use integration is required.

Create a private directory and a random token. Keep this shell open; runner configuration and raw test logs stay in this directory. For multiple devices, use a separate runner, port, and token for each device, and merge their entries into one configuration file.

```sh
export MRA_NATIVE_DIR="$(mktemp -d /tmp/mra-native.XXXXXX)"
export MARIONETTE_AGENT_NATIVE_RUNNERS="$MRA_NATIVE_DIR/runners.json"
export MRA_NATIVE_TOKEN="$(openssl rand -hex 24)"
```

### iOS Simulator

Replace `IOS_UDID` with the exact booted Simulator UUID and set the bundle ID of the app to inspect. Build the standalone UI test bundle, configure its environment, and start its long-running test. The runner never launches or activates the target app; open the app after the test runner starts. It observes SpringBoard when a system alert is present or the target app is not foreground, otherwise the configured app.

```sh
export MRA_NATIVE_PLATFORM=ios
export MRA_NATIVE_DEVICE=IOS_UDID
export MRA_NATIVE_PORT=18741
export MRA_APP_BUNDLE_ID=com.example.example
xcodegen generate --spec packages/marionette_agent_ios/native/project.yml
xcodebuild build-for-testing \
  -project packages/marionette_agent_ios/native/MarionetteNative.xcodeproj \
  -scheme MarionetteNative -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MRA_NATIVE_DIR/ios-build" > "$MRA_NATIVE_DIR/build.log" 2>&1
python3 - <<'PYCODE'
import glob, os, plistlib
path = glob.glob(os.environ["MRA_NATIVE_DIR"] + "/ios-build/Build/Products/*.xctestrun")[0]
with open(path, "rb") as file:
    settings = plistlib.load(file)
target = settings["MarionetteNative"]
target["EnvironmentVariables"].update({
    "MRA_NATIVE_PORT": os.environ["MRA_NATIVE_PORT"],
    "MRA_NATIVE_TOKEN": os.environ["MRA_NATIVE_TOKEN"],
    "MRA_APP_BUNDLE_ID": os.environ["MRA_APP_BUNDLE_ID"],
})
target["TestTimeoutsEnabled"] = False
with open(path, "wb") as file:
    plistlib.dump(settings, file)
PYCODE
xcodebuild test-without-building \
  -xctestrun "$MRA_NATIVE_DIR"/ios-build/Build/Products/*.xctestrun \
  -destination "id=$MRA_NATIVE_DEVICE" -parallel-testing-enabled NO \
  > "$MRA_NATIVE_DIR/runner.log" 2>&1 &
MRA_NATIVE_PID=$!
```

### Android emulator

Replace the serial with the exact emulator. The two APKs are the instrumentation host and its test runner. These setup commands use adb only to install/start the runner and forward its loopback port. Element retrieval and input inside the runner use `UiDevice` / `UiObject2`; the native command implementation does not run adb, shell input, or XML dumps.

```sh
export MRA_NATIVE_PLATFORM=android
export MRA_NATIVE_DEVICE=emulator-5554
export MRA_NATIVE_PORT=18742
packages/marionette_agent_android/native/gradlew \
  -p packages/marionette_agent_android/native assembleDebug assembleDebugAndroidTest
adb -s "$MRA_NATIVE_DEVICE" install -r \
  packages/marionette_agent_android/native/build/outputs/apk/debug/MarionetteNative-debug.apk
adb -s "$MRA_NATIVE_DEVICE" install -r \
  packages/marionette_agent_android/native/build/outputs/apk/androidTest/debug/MarionetteNative-debug-androidTest.apk
adb -s "$MRA_NATIVE_DEVICE" forward "tcp:$MRA_NATIVE_PORT" "tcp:$MRA_NATIVE_PORT"
adb -s "$MRA_NATIVE_DEVICE" shell am instrument -w \
  -e class dev.marionette.nativeui.NativeRunner \
  -e device "$MRA_NATIVE_DEVICE" -e port "$MRA_NATIVE_PORT" -e token "$MRA_NATIVE_TOKEN" \
  dev.marionette.nativeui.test/androidx.test.runner.AndroidJUnitRunner \
  > "$MRA_NATIVE_DIR/runner.log" 2>&1 &
MRA_NATIVE_PID=$!
```

### Connect the CLI

Run this after the setup for your platform. The JSON file maps platform and exact device ID to a loopback port and token. Start a fresh CLI runtime with this environment; an already-running daemon does not inherit new environment variables. Other terminals and MCP launchers must receive both exported paths. A missing mapping returns `UNSUPPORTED_CAPABILITY`; an unavailable runner returns `IO_ERROR`.

```sh
python3 - <<'PYCODE'
import json, os
path = os.environ["MARIONETTE_AGENT_NATIVE_RUNNERS"]
if os.path.exists(path):
    with open(path) as file:
        config = json.load(file)
else:
    config = {}
config.setdefault(os.environ["MRA_NATIVE_PLATFORM"], {})[os.environ["MRA_NATIVE_DEVICE"]] = {
    "port": int(os.environ["MRA_NATIVE_PORT"]), "token": os.environ["MRA_NATIVE_TOKEN"]
}
with open(path, "w") as file:
    json.dump(config, file)
os.chmod(path, 0o600)
PYCODE
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_NATIVE_DIR/runtime"
marionette-agent --session app session bind \
  --platform "$MRA_NATIVE_PLATFORM" --device "$MRA_NATIVE_DEVICE"
marionette-agent --session app snapshot
```

The initial snapshot may report a connection error while the test runner starts. Retry observation once it is ready. Keep one operator per device: separate runtimes and external tools are independent of the daemon's per-device queue.

## Observe and respond to a permission dialog

`snapshot` observes Flutter when connected, native when bound, and both when the session has both. Use `--source flutter|native|all` to choose explicitly. Every snapshot replaces previous refs from both sources. Mixed output identifies each element's source and coordinate space; it does not merge duplicate controls. Native rows appear first. A failed requested source fails the observation and retires refs; an empty/root-only native result carries a limitation.

Read the actual label and ref before choosing a response; labels vary with language and OS. Replace these refs with the current snapshot's values. `@e` routes to Flutter and `@n` to native, using the same command. Source cannot override a ref. `connect` can run before or after `session bind`; the device association is your declaration, not verification that both connections target the same app.

```sh
marionette-agent --session app snapshot
marionette-agent --session app tap @e1
marionette-agent --session app snapshot
marionette-agent --session app tap @n1
marionette-agent --session app snapshot
```

Native exact `--text`, `--identifier`, or `--type` selectors require `--source native`. Unqualified selectors and coordinates keep their Flutter meaning. Zero or multiple matches fail without input. Known native alerts block Flutter input and suppress Flutter refs in mixed snapshots. Other occlusion remains unknown: inspect the device and choose a native control when a picker covers Flutter.

## Select a photo or swipe

Open the picker with `tap`, observe it with `snapshot`, and tap a current photo or confirmation ref. The same `swipe` accepts either source's ref and a finger direction. Native distance uses its screen coordinate space. The following refs and coordinates are examples; inspect your device's current bounds first.

```sh
marionette-agent --session app swipe @e2 left --distance 200
marionette-agent --session app snapshot
marionette-agent --session app swipe @n8 up --distance 200
marionette-agent --session app snapshot
marionette-agent --session app swipe --source native \
  --start-x 360 --start-y 1000 --end-x 360 --end-y 400
marionette-agent --session app snapshot
marionette-agent --session app tap --source native --text Allow
```

Native coordinate tap uses `tap --source native --x X --y Y`. iOS uses screen points and platform-default drag velocity; Android uses physical pixels rounded to integers and 60 swipe steps (about 300ms). Account for orientation and scale. No coordinate fallback or cross-source retry occurs. Native supports compact and exact text/identifier/type snapshot filters; use `--source flutter` for interactive, depth, or key filters. Native fill and other unsupported actions fail before input.

## References, policies, and errors

`--json`, `--content-boundaries`, `--max-output`, deadlines, and normal errors apply. Undisclosed refs are unusable. Ref operations reobserve their source before sending one input; moved, missing, or duplicate targets fail. Observation and input are not atomic OS operations.

Native input expires same-device native refs across sessions and all Flutter refs in the daemon. Flutter input expires both observations in its session and other sessions bound to the same device. Rebinding expires both observations and pending approvals. Reads other than snapshot preserve refs. Native tap/swipe retain the `native` policy action. After `outcome: unknown`, observe the actual screen before deciding the next action; never automatically resend.

MCP's `core` profile exposes `marionette_agent_session_bind`, `marionette_agent_snapshot`, `marionette_agent_tap`, and `marionette_agent_swipe`. The former native command, native MCP tools, and native profile are removed. Batch routes tap/swipe and snapshot through the same service on a bound session. Workflow snapshot can observe both sources on a bound session, while workflow v1's mutation selectors remain Flutter-only.

## Stop your runner

```sh
marionette-agent --session app close
kill "$MRA_NATIVE_PID"
wait "$MRA_NATIVE_PID" || true
```

For Android, also stop `dev.marionette.nativeui` with `adb -s "$MRA_NATIVE_DEVICE" shell am force-stop dev.marionette.nativeui` and remove the owned forwarding with `adb -s "$MRA_NATIVE_DEVICE" forward --remove "tcp:$MRA_NATIVE_PORT"`. Stop your app and release your own emulator/Simulator separately. Closing the CLI session does not terminate an externally started runner or device.
