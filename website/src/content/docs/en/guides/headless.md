---
title: Launch an execution environment
description: Launch tester, iOS, Android, macOS, or Web headlessly and clean up owned resources.
---

`launch` builds and starts an app in the selected environment, connects it, and completes the first observation. The host is macOS. Select an environment explicitly; failures do not trigger an automatic fallback to another platform.

## Prepare the environment

Install the Flutter SDK, resolve project dependencies, and prepare the chosen platform’s SDK and devices. `launch` builds with `--no-pub`, so run `flutter pub get` in the app directory first. Set a timeout that includes the initial build.

| Platform  | Purpose and additional requirements                                                  |
| --------- | ------------------------------------------------------------------------------------ |
| `tester`  | Shared Flutter UI checks; verified with Flutter 3.47.2                               |
| `ios`     | Boots in a private device set; requires Xcode and installed device type and runtime  |
| `android` | Boots an existing AVD without a window; requires Android SDK and an unused even port |
| `macos`   | Native app; requires app-side hidden-window support                                  |
| `web`     | Headless Chrome; requires Google Chrome                                              |

## Start small with tester

Run from the repository root after resolving dependencies.

```sh
marionette-agent --session fast --timeout 600000 launch ./example --platform tester
marionette-agent --session fast snapshot
marionette-agent --session fast fill --key text_input 'headless check'
marionette-agent --session fast snapshot
marionette-agent --session fast --timeout 60000 close
```

Tester runs the debug Flutter engine. In the verified SDK, its logical viewport is 800×600 with DPR 3. It does not reproduce native iOS or Android functionality or physical-device performance.

## Select iOS or Android

iOS requires `--device-type` and `--runtime`; Android requires `--avd` and `--port`. Replace the example identifiers and names below with resources available on your host.

```sh
marionette-agent --session ios --timeout 600000 launch ./example --platform ios \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
marionette-agent --session ios --timeout 60000 close

marionette-agent --session android --timeout 600000 launch ./example --platform android \
  --avd Pixel_9_Pro --port 5586
marionette-agent --session android --timeout 60000 close
```

The Android port must be an unused even number from 5554 to 5682. The AVD runs read-only and does not persist changes to its saved state. Only one managed app may run per project to prevent conflicts in shared build output.

Select macOS or Web with `--platform` as well. The CLI does not automatically adapt an arbitrary macOS app to hidden operation. Refer to the example’s hidden window and debug rendering support. Use a logged-in GUI environment; do not assume operation on a host without WindowServer.

## Record and clean up

Once connected, use the regular CLI operations. Choose `--platform flutter` for [recording Flutter rendering](/marionette_agent/en/guides/capture/).

`close` finalizes recording, then terminates the app and device owned by the session. It does not stop shared Simulators or the entire adb server. Cleanup is attempted after launch failure or timeout, but there is no automatic recovery after host shutdown or forced termination. App exit invalidates refs and does not trigger an automatic restart.
