---
title: Capture images and video
description: Record the post-action state with screenshots, annotations, and video.
---

Save the screen to compare the CLI response with what the app actually displayed. Create parent directories first and choose a new filename for each run.

## Take a screenshot

```sh
mkdir -p artifacts
marionette-agent screenshot artifacts/after.png
marionette-agent screenshot artifacts/after.jpg --screenshot-format jpeg
```

PNG is the default. Select JPEG explicitly with `--screenshot-format jpeg`; set `--screenshot-quality` from 0 to 100 to change quality. The extension alone does not select the format. Transparent pixels are composited onto white for JPEG.

Omitting the path saves into a private temporary directory and returns the path. You can also select an existing directory with `--screenshot-dir`. Existing files are not overwritten.

## Include iOS dialogs and the keyboard

The default `--source flutter` captures Flutter rendering and keeps existing tester workflows working. For OS UI, select `ios-simulator` and set `SIMULATOR_UDID` to the exact UDID of a booted iOS Simulator in the default device set. Names and `booted` are rejected even if only one device is running. Use a macOS host with full Xcode selected; no app connection or Marionette binding is needed for this capture.

```sh
marionette-agent screenshot artifacts/os-ui.png \
  --source ios-simulator --device "$SIMULATOR_UDID" --json
marionette-agent screenshot artifacts/os-ui.jpg \
  --source ios-simulator --device "$SIMULATOR_UDID" --screenshot-format jpeg
```

The saved image includes the selected device's visible permission dialog, photo picker, software keyboard, status bar and safe-area regions. It captures the full internal framebuffer at native resolution, without a notch/corner mask, device bezel or Mac window decoration. Mac window zoom does not affect the image. Wait for rotation to settle: `capture.pixelWidth/pixelHeight` report saved dimensions, and `capture.orientation` reports their aspect (portrait/landscape/square), not a sensor angle. On the tested iPhone 17 Pro / iOS 26.2 runtime, landscape UI remains in a 1206×2622 portrait framebuffer; the image is deliberately not auto-rotated. The result also identifies the source, UDID, runtime, display, scope, mask and physical-pixel coordinate space.

The explicit UDID controls capture even if your session is connected to another app. Use a dedicated Simulator with dummy photos and inspect evidence before sharing. Protected or restricted content is not guaranteed; the CLI never changes permissions, dismisses dialogs or bypasses restrictions. Acquisition failure never falls back to Flutter rendering. Formats, quality, destination selection, exclusive creation and the original timeout work as above.

Native screenshots cannot use Flutter ref annotation, target crop, or `diff screenshot`. Those features rely on a different coordinate contract; native annotation/crop fail explicitly. Use the same `source` and `device` fields in the MCP screenshot tool. A workflow screenshot step uses this route too; see [workflow steps](/marionette_agent/en/guides/workflows/).

Physical iOS devices are **unsupported**: `--source ios-device --device <id>` returns `UNSUPPORTED_CAPABILITY`. They need a separately signed XCTest runner, pairing/trust, Developer Mode and compatible OS/Xcode tooling; simctl is Simulator-only. See [the capture contract and feasibility notes](https://github.com/r0227n/marionette_agent/blob/develop/docs/SPEC.md#native-ios-screenshots).

## Overlay refs on the image

```sh
marionette-agent snapshot
marionette-agent screenshot --annotate artifacts/targets.png
```

Annotations require a current valid snapshot and a mapped screenshot provider. The example supports this. Retake the snapshot if you performed a UI action in between. Use the image to relate ref numbers to their targets.

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
