---
title: Capture images and video
description: Capture iOS system UI with XCUIScreen and record app or device video.
---

Save the screen to compare the CLI response with the actual display. Screenshots use Apple's `XCUIScreen.main.screenshot()` in a bundled XCTest UI-test runner. Set `SIMULATOR_UDID` to the exact UDID of a booted iOS Simulator; names and `booted` are rejected. Use macOS with full Xcode selected. No app connection, Marionette binding, or app-side screenshot provider is needed.

## Take a screenshot

```sh
mkdir -p artifacts
marionette-agent --timeout 120000 screenshot artifacts/after.png --device "$SIMULATOR_UDID"
marionette-agent --timeout 120000 screenshot artifacts/after.jpg --device "$SIMULATOR_UDID" --screenshot-format jpeg
```

The default source is `ios-simulator`. The CLI builds its own runner on the first capture and reuses that build for the daemon's lifetime. Allow time for compilation and XCTest startup with `--timeout`; its deadline also includes image recovery, conversion and saving. No changes to your app's Xcode project are needed. Compiled CLI installations contain the same runner sources.

The PNG includes visible OS permission dialogs, photo pickers, software keyboard, status bar and safe-area content. The runner observes the main screen without launching/activating the observed app or tapping UI. The explicit UDID controls capture even if your session is connected to another app. Use a dedicated Simulator with dummy data and inspect shared evidence.

Results include `capture.method: xcuiscreen`, source, device UDID, runtime, `display: main`, `scope: device-screen`, `mask: system-default`, physical-pixel dimensions and raster orientation. XCUIScreen supplies its system image without a configurable notch/corner mask; Mac window decorations and zoom are irrelevant. Wait for rotation to settle, then compare the returned dimensions with the saved PNG. `orientation` describes the image aspect, not sensor position. The CLI does not rotate or resize pixels. Landscape XCUIScreen PNGs can retain portrait raster dimensions with EXIF orientation; JPEG preserves that orientation tag.

PNG is the default. Select JPEG explicitly with `--screenshot-format jpeg`; quality is 0–100 using `--screenshot-quality`. Extensions do not select the format. JPEG composites transparency onto white. Omit the path for a private temporary output, or use `--screenshot-dir` with an existing directory. Parent directories must exist and existing files are never overwritten.

## Capture Android system UI

Select `--source android-emulator` and set `CAPTURE_PAIRING` to a private pairing file. Follow the [capture agent setup](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent_android/capture_agent/README.md) to prepare the pairing and start its Instrumentation with Android Studio or Gradle. That separate setup environment uses Android debugging transport internally. Leave the agent running. The screenshot command calls UI Automator through authenticated local TCP; it executes no ADB commands and needs no Flutter connection.

```sh
marionette-agent screenshot artifacts/android.png --source android-emulator --device "$CAPTURE_PAIRING"
marionette-agent screenshot artifacts/android.jpg --source android-emulator --device "$CAPTURE_PAIRING" --screenshot-format jpeg
```

Only an Emulator with a single display 0 is supported. The result uses `method: uiautomator` and the existing PNG/JPEG, exclusive saving and physical-pixel metadata. Permission dialogs, photo/file pickers, IME and system bars are included. Rotation uses the current display pixels. FLAG_SECURE can produce hidden content or an error; black pixels alone do not establish protection. No failure falls back to Flutter or another source. MCP/workflow also accept `source: android-emulator` and the pairing file as `device`. Existing iOS capture remains the default.

## Migrate existing capture commands

The Marionette/Flutter screenshot route, ref/selector crop, `--annotate`, and the example mapped provider have been removed. Every screenshot now requires a device. Screenshot capture is available for iOS Simulator and Android Emulator; Flutter tester rendering recording is unavailable.

MCP screenshot requires `device`; optional `source` defaults to `ios-simulator`. Workflow screenshot steps use the same route and require a literal `device`: an iOS UDID or Android pairing file. A screenshot-only workflow needs no connection. See [workflow steps](/marionette_agent/en/guides/workflows/).

```sh
marionette-agent --timeout 120000 diff screenshot --device "$SIMULATOR_UDID" --baseline artifacts/after.png --output artifacts/difference.png
```

Image diff captures the selected source again. Use a PNG baseline from the same device, capture method and settled orientation; dimensions must match. The threshold compares physical pixels without mapping Flutter refs.

Physical iOS devices remain unsupported in this implementation: `--source ios-device --device <id>` returns `UNSUPPORTED_CAPABILITY`. Signing/provisioning and a verified physical-device runner lifecycle are not implemented. Protected or restricted content is not guaranteed. Capture failures never select another source, close dialogs or repeat app actions. See the [capture contract](https://github.com/r0227n/marionette_agent/blob/develop/docs/SPEC.md#native-ios-screenshots).

## Native platform recording

Recording never uses Marionette or a VM Service connection. `--platform flutter` and its isolated screenshot connection have been removed; unsupported capture does not fall back to Flutter. The host is macOS with the bundled native video libraries.

| Platform | Device                                     | Acquisition and output                                                                                           |
| -------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| ios      | Booted Simulator UDID                      | A bundled, persistent XCTest runner calls `XCUIScreen.main.screenshot()`; H.264 MP4                              |
| android  | Private UI Automator pairing file          | The existing capture instrumentation calls `UiDevice.takeScreenshot`; Emulator display 0; H.264 MP4              |
| macos    | Active display number, starting at 1       | ScreenCaptureKit `SCStream` and `SCRecordingOutput`; macOS 15+, Xcode and Screen Recording permission; H.264 MOV |
| web      | `ws://127.0.0.1:<port>/devtools/page/<ID>` | Chromium CDP `Page.captureScreenshot`; page viewport, including headless Chrome; H.264 MP4                       |

Platform, device and a new output path are required. Relative paths and Android pairing paths resolve against the caller's cwd. Existing files, directories and symlinks are rejected. Recording owns a session and reserves the explicit target within a daemon until capture terminates. Web pages do not reserve macOS displays. Pair the Android instrumentation separately using the screenshot setup; stopping recording leaves that caller-owned instrumentation running. iOS builds and owns its runner without launching the observed app. Device inventory/runner cleanup may use simctl, but never simctl image/video capture. No adb screenrecord or screencapture recording remains.

The iOS/Android/Web backends sample platform PNGs and encode actual monotonic acquisition times as VFR, rather than claiming native video-stream frame rates. `--fps 1..60` sets the delay after each sample (default 10); capture and transfer add latency and fast animations may be missed. Temporary disk usage grows with duration. A size change fails explicitly. macOS uses the requested minimum frame interval (default 30fps). All recordings are silent. Protected content is not guaranteed. Web excludes browser chrome and OS dialogs; iOS/Android include the visible device screen. macOS records the selected display, including other applications, and does not follow windows.

Start confirms the first valid PNG or ScreenCaptureKit's recording-start callback. The request deadline includes runner build/start, with a maximum backend startup wait of 120 seconds; allow `--timeout 120000` on first iOS use. Stop/close wait for finalization and saving. Repeated stop returns the same result. Restart finalizes the old video before starting the new destination. No automatic restart, capture-source fallback, or UI replay occurs. Capture errors and Chromium disconnection fail recording. Encoding has a 30-second deadline. Native work continues bounded cleanup after a request timeout.

States are idle/starting/recording/stopping/stopped/failed. Successful data includes platform, device, path, startedAt, elapsedMs and bytes; elapsedMs is wall time, not media duration. Failed status includes failure and recoveryPath. Files are staged privately next to the exclusively reserved destination. Failed finalization retains recovery data. Shutdown waits up to 60 seconds, then bounds forced cleanup to five seconds. SIGKILL/host shutdown recovery is unsupported. Recording never changes action refs or VM connection generations.

Chromium requires a dedicated debug profile and loopback remote debugging. Select the exact page endpoint from `/json/list`; ports are 1–65535 and IDs uppercase alphanumeric. Remote hosts, credentials, queries, browser endpoints, old `display:N@` prefixes and MOV output are rejected. Missing capabilities return UNSUPPORTED_CAPABILITY, disconnection CONNECTION_LOST, rejected/malformed capture IO_ERROR. Raw server messages are not exposed. Web needs no macOS screen-recording permission. Android physical devices and iOS physical devices are outside this implementation's scope.

```sh
marionette-agent --timeout 120000 record start artifacts/ios.mp4 --platform ios --device "$SIMULATOR_UDID"
marionette-agent record stop
marionette-agent record start artifacts/android.mp4 --platform android --device "$CAPTURE_PAIRING"
marionette-agent record stop
marionette-agent record start artifacts/macos.mov --platform macos --device 1
marionette-agent record stop
marionette-agent record start artifacts/web.mp4 --platform web --device "$CHROME_PAGE_ENDPOINT"
marionette-agent record stop
```

## macOS screenshots

Select a display explicitly without a Flutter connection. The image includes the whole display and other apps; inspect it before sharing. The invoking terminal/host app needs Screen Recording permission. Visible panels and menus are included; protected UI, other Spaces and displays are not guaranteed. Capture does not follow moving windows. Missing permission, topology changes and timeout return errors.

```sh
marionette-agent device list --platform macos
marionette-agent screenshot --source macos --display 1 artifacts/native.png
```

macOS still images use XCTest/XCUIScreen and require full Xcode. Allow `--timeout 120000` for the initial runner build. Non-main capture with more than two active displays is unsupported.
