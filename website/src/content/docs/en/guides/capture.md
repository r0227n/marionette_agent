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

## Include native macOS UI

With a connected session, inspect the display list and select its current index. This example selects the main display (1). The default Flutter capture is unchanged.

```sh
marionette-agent device list --platform macos
marionette-agent screenshot --source macos --display 1 artifacts/native.png
marionette-agent screenshot --source macos --display 1 artifacts/native.jpg --screenshot-format jpeg
```

The entire selected display is captured, including other apps and personal information; inspect images before sharing. Visible file panels, menus and capturable permission dialogs are included, but other displays/Spaces, hidden windows and protected UI are not guaranteed. Capture does not follow moving windows and includes occluding content. Flutter ref annotations and target crops are unavailable for native captures.

The invoking terminal/host app needs Screen Recording permission. Missing permission, a lost display and timeout fail without switching to Flutter images. Result `capture` metadata reports the display index/ID, pixel dimensions, scope and scale. MCP screenshot uses the same route with `source: "macos"` and integer `display`. `diff screenshot` remains Flutter-only.

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
