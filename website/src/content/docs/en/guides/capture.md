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

The Marionette/Flutter screenshot route, ref/selector crop, `--annotate`, and the example mapped provider have been removed. Every screenshot now requires a device. Screenshot capture is available for iOS Simulator and Android Emulator; Flutter tester and other app runtimes can use [Flutter rendering video](#record-the-flutter-rendering).

MCP screenshot requires `device`; optional `source` defaults to `ios-simulator`. Workflow screenshot steps use the same route and require a literal `device` UDID. A screenshot-only workflow needs no connection. See [workflow steps](/marionette_agent/en/guides/workflows/).

```sh
marionette-agent --timeout 120000 diff screenshot --device "$SIMULATOR_UDID" --baseline artifacts/after.png --output artifacts/difference.png
```

Image diff takes a fresh XCUIScreen capture. Use a PNG baseline from the same device, capture method and settled orientation; dimensions must match. The threshold compares physical pixels without mapping Flutter refs.

Physical iOS devices remain unsupported in this implementation: `--source ios-device --device <id>` returns `UNSUPPORTED_CAPABILITY`. Signing/provisioning and a verified physical-device runner lifecycle are not implemented. Protected or restricted content is not guaranteed. Capture failures never select another source, close dialogs or repeat app actions. See the [capture contract](https://github.com/r0227n/marionette_agent/blob/develop/docs/SPEC.md#native-ios-screenshots).

## Record the Flutter rendering

Prepare a connected session and a complete CLI installation with its bundled native libraries. The same command works for Flutter rendering in headless environments.

```sh
marionette-agent record start artifacts/interaction.mp4 --platform flutter
marionette-agent tap --key tap_button
marionette-agent snapshot
marionette-agent record status
marionette-agent record stop
```

This saves one Flutter view as silent H.264 video. `--fps` controls the capture interval and defaults to 10. Frames use actual capture timestamps, so a fixed frame rate is not guaranteed. OS keyboards, dialogs, browser chrome, and platform views may not be captured.

## Record the device screen

To capture an iOS Simulator screen, set `SIMULATOR_UDID` in this shell to the device’s UDID. A VM Service connection is not required.

```sh
marionette-agent record start artifacts/device.mp4 \
  --platform ios --device "$SIMULATOR_UDID"
marionette-agent record stop
```

Android uses a device serial; macOS uses a display number. Web requires a display number combined with the selected Chrome page’s loopback debugging WebSocket URL, such as `display:1@ws://127.0.0.1:9222/devtools/page/ACTUALID`. See the [Web targeting contract](https://github.com/r0227n/marionette_agent/blob/develop/docs/cli-reference.md#web-recording) for setup and restrictions. macOS and Web screen recording require OS permission. Web mode records the selected display rather than limiting capture to the page viewport.

`record restart` finalizes the current recording before starting a new destination. A failed new recording does not restore the previous one. `stop` waits for video finalization, so allow a sufficient timeout for longer recordings.

See [capture and recording details](https://github.com/r0227n/marionette_agent/blob/develop/docs/cli-reference.md#capture) for naming, exclusive writes, deadlines, finalization, and recovery.
