---
title: Operate and record headless apps
description: Choose tester, iOS, Android, macOS, or Web, launch without a window, record Flutter rendering, and clean up or recover.
---

Headless execution lets you observe and operate Flutter UI without displaying the app window. `launch` builds and starts a debug app in the selected environment, connects to its VM Service, and completes the first observation. Then use the same snapshot, tap, fill, and workflow commands, checking results through images or video.

The host is macOS. Hiding the app window does not remove the need for a GUI environment or platform SDKs. The target app must [initialize Marionette](/marionette_agent/en/getting-started/app-integration/).

## Choose an environment for your check

| Platform  | How it runs without a window               | Suitable checks and requirements                                        |
| --------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| `tester`  | Flutter test engine                        | Repeated shared Flutter UI checks; verified with Flutter 3.47.2         |
| `ios`     | Dedicated Simulator device set             | iOS behavior; requires Xcode and installed device type/runtime          |
| `android` | Existing AVD with `-no-window`             | Android behavior; requires Android SDK, an AVD, and an unused even port |
| `macos`   | Hidden NSWindow with rendering kept active | macOS app; requires app support and a logged-in GUI session             |
| `web`     | Headless Chrome                            | Flutter Web behavior; requires Google Chrome                            |

Tester does not reproduce native iOS or Android implementations. Check OS plugins, permissions, keyboards, Web-specific code, and physical-device performance in the relevant environment. A visual platform override does not change the execution OS. Failures do not trigger automatic environment switching or UI action replay.

## Prepare dependencies before launch

Finish [CLI installation](/marionette_agent/en/getting-started/installation/) and resolve the example’s dependencies. Run this from the repository root.

```sh
cd example
flutter pub get
cd ..
```

`launch` builds with `--no-pub`. Allow enough timeout for the first build and device boot. Recording also needs ffmpeg on PATH and disk space for temporary PNGs and video.

## Verify an interaction with tester

```sh
marionette-agent --session fast --timeout 600000 launch ./example --platform tester
marionette-agent --session fast snapshot
marionette-agent --session fast tap --key tap_button
marionette-agent --session fast get text --key tap_result
marionette-agent --session fast fill --key text_input 'headless check'
marionette-agent --session fast snapshot
marionette-agent --session fast screenshot
```

Compare observations and the saved image: `tap_result` should increase and the input should change. A successful command response alone does not guarantee the intended visual effect. When using refs, take a fresh snapshot after each action.

In the verified SDK, tester is debug-only with an 800×600 logical viewport and DPR 3. Scroll off-screen elements into view and choose swipe distances for that viewport. This example workflow opens Controls, scrolls up by 200px, then swipes left by 500px.

```sh
marionette-agent --session fast workflow run \
  packages/marionette_agent/examples/workflows/headless-controls.yaml --json
```

Check that `page_result` in `finalSnapshot` is `Current page: 2`. These distances are specific to the example, not defaults for other apps. See the [workflow guide](/marionette_agent/en/guides/workflows/) for failure progress and reobservation.

## Record Flutter rendering

Use the session launched above. Choose a new output path for every recording.

```sh
mkdir -p artifacts
marionette-agent --session fast record start artifacts/headless.mp4 --platform flutter --fps 10
marionette-agent --session fast tap --key tap_button
marionette-agent --session fast snapshot
marionette-agent --session fast record status --json
marionette-agent --session fast --timeout 60000 record stop --json
marionette-agent --session fast --timeout 60000 close
```

The video is a silent H.264 MP4 of one Flutter view. Omit `--device`. OS keyboards/dialogs, browser UI, and platform views are not guaranteed to appear; macOS screen recording permission is unnecessary. For a full OS screen, choose a [device recording](/marionette_agent/en/guides/capture/) mode.

Fps accepts 1–60 and defaults to 10. The recorder waits the requested interval after each PNG capture and uses actual timestamps for VFR output. A fixed frame rate or every fast-animation frame is not guaranteed. Stop waits for video conversion. On TIMEOUT, inspect `record status` for the final state; on failure, inspect `failure/recoveryPath`. Dimension changes, connection loss, and conversion failure are not replaced with a successful blank video.

## Check iOS and Android

Close the previous session before switching environments. Only one managed app may run per project at a time. Inspect available identifiers and AVDs first.

```sh
xcrun simctl list devicetypes
xcrun simctl list runtimes
emulator -list-avds
```

The following identifiers and AVD name are examples. Substitute installed resources.

```sh
marionette-agent --session ios --timeout 600000 launch ./example --platform ios \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
marionette-agent --session ios snapshot
marionette-agent --session ios --timeout 60000 close

marionette-agent --session android --timeout 600000 launch ./example --platform android \
  --avd Pixel_9_Pro --port 5586
marionette-agent --session android snapshot
marionette-agent --session android --timeout 60000 close
```

iOS uses a dedicated device set isolated from the default set. Android ports must be unused even numbers from 5554–5682. The existing AVD runs read-only with no-snapshot and no-window, without persisting changes to its saved state. The AVD itself is not created or deleted. Both environments support `--platform flutter` recording.

## Check macOS and Web

```sh
marionette-agent --session macos --timeout 600000 launch ./example --platform macos
marionette-agent --session macos snapshot
marionette-agent --session macos --timeout 60000 close

marionette-agent --session web --timeout 600000 launch ./example --platform web
marionette-agent --session web snapshot
marionette-agent --session web --timeout 60000 close
```

On macOS, the native side must hide NSWindow and start FlutterEngine, while Dart’s `enableHeadlessRendering()` keeps hidden rendering active, as implemented in the example. Launch passes `MARIONETTE_HEADLESS=1` and the Dart define but does not modify arbitrary apps. Do not assume support on a host without WindowServer.

Web starts Chrome headlessly. Use `record --platform flutter` for hidden Flutter Web rendering as well. `record --platform web` is a separate mode that records a visible macOS display.

## Launch options and ownership

Use `--flutter` to select the Flutter executable and `--target` to select the entrypoint, default `lib/main.dart`. iOS requires device-type/runtime; Android requires avd/port. Mixing options from another platform is an argument error.

Success data and `session show` include `application:{platform,state,pid,device?}`. State is running/exited; pid identifies the owned runner. Launch success confirms VM Service connectivity and the first Marionette observation, not merely process existence.

Close finalizes recording before terminating the session’s owned app and device. It leaves shared Simulators and the overall adb server running. Launch failure or timeout also cleans up owned resources, although bounded cleanup can continue after the response. App exit invalidates the connection and refs without automatic restart. There is no automatic recovery after SIGKILL or host shutdown.

Apps you start yourself and attach through connect remain running after close. See [manual headless setup](/marionette_agent/en/guides/manual-headless/) when you need to manage the runner yourself.

## Troubleshooting

| Symptom                               | What to check                                                                          |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| SESSION_CONFLICT                      | Another launch owns the session/project/Android port; close the earlier session        |
| Launch TIMEOUT                        | Allow enough first-build/boot time; inspect session show after cleanup                 |
| UNSUPPORTED_CAPABILITY                | Check SDK executables, Chrome, ffmpeg, and required app capabilities                   |
| Unchanging macOS image                | Implement both native window handling and Dart rendering support                       |
| Visible iOS window                    | Use a dedicated device set and avoid opening it in Simulator.app                       |
| Slow or stopped recording             | Check PNG capture time, disk space, host sleep, dimension changes, and connection loss |
| Screenshot/record persistence failure | Ensure the parent directory exists and the output path is new                          |
