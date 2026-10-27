---
title: Native dialogs and photo pickers
description: Inspect, tap, and swipe iOS Simulator and Android system UI with XCUITest and UI Automator runners.
---

Use `native` when a permission dialog or system photo picker covers the Flutter view. These commands operate the explicit device without a Flutter VM connection. iOS uses XCUITest / XCUIAutomation; Android calls UI Automator APIs directly. The CLI sends authenticated requests to a local test runner. Native screenshots are outside this feature's scope.

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
marionette-agent --session app native snapshot \
  --platform "$MRA_NATIVE_PLATFORM" --device "$MRA_NATIVE_DEVICE"
```

The initial snapshot may report a connection error while the test runner starts. Retry observation once it is ready. Keep one operator per device: separate runtimes and external tools are independent of the daemon's per-device queue.

## Respond to a permission dialog

Read the actual label and ref before choosing a response; labels vary with language and OS. Replace `@n1` with the ref from your snapshot. After input, observe again. The final Flutter `snapshot` requires the usual `connect` and confirms that control returned to the app.

```sh
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app native tap @n1 --platform ios --device IOS_UDID
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app snapshot
```

Exact `--text`, `--identifier`, or `--type` selectors are alternatives to a ref. Zero or multiple matches fail without input. Native `@n` refs cannot be used as Flutter `@e` refs.

## Select a photo or swipe

Open the picker from your app, inspect it with `native snapshot`, and tap the current photo or confirmation ref. For a swipe, choose coordinates from the current device screen or observed bounds, then inspect the result and use a fresh ref. The following coordinates and ref are examples, not universal picker locations.

```sh
marionette-agent --session app native swipe --platform android --device emulator-5554 \
  --start-x 360 --start-y 1000 --end-x 360 --end-y 400
marionette-agent --session app native snapshot --platform android --device emulator-5554
marionette-agent --session app native tap @n8 --platform android --device emulator-5554
```

Coordinate `tap --x X --y Y` is also available. iOS coordinates are screen points, with the platform's default drag velocity; Android coordinates are physical pixels, rounded to integers, with 60 swipe steps (about 300ms). Orientation and scale matter. Accessibility can omit controls; an empty/root-only snapshot reports a limitation. There is no automatic fallback to coordinates. View the Simulator/emulator directly if the target is missing; screen capture is a separate feature.

## References, policies, and errors

Native snapshots return `source: native`, platform, device, coordinate space, generation, and normalized elements with bounds. `--json`, `--content-boundaries`, `--max-output`, deadlines, and the normal error envelope apply. Ref taps reobserve the full element, including bounds, before sending one input. A moved, missing, or duplicate target fails; observation and input are not atomic OS operations.

Native tap/swipe expire native refs for that device across sessions and all Flutter refs in the daemon. A Flutter mutation expires its session's native refs. Reads preserve Flutter refs. Policies control tap/swipe under `native`. After a post-dispatch failure or timeout with `outcome: unknown`, observe the actual screen before deciding what to do next; never automatically resend.

MCP `--tools core,native` exposes `marionette_agent_native_snapshot`, `marionette_agent_native_tap`, and `marionette_agent_native_swipe`. Every call requires platform and device. Native commands are excluded from batch and workflow v1.

## Stop your runner

```sh
marionette-agent --session app close
kill "$MRA_NATIVE_PID"
wait "$MRA_NATIVE_PID" || true
```

For Android, also stop `dev.marionette.nativeui` with `adb -s "$MRA_NATIVE_DEVICE" shell am force-stop dev.marionette.nativeui` and remove the owned forwarding with `adb -s "$MRA_NATIVE_DEVICE" forward --remove "tcp:$MRA_NATIVE_PORT"`. Stop your app and release your own emulator/Simulator separately. Closing the CLI session does not terminate an externally started runner or device.
