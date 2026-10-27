---
title: Capture images and video
description: Record the post-action state with screenshots, annotations, and video.
---

Screenshots use the Android UI Automator API on an Emulator. A standalone screenshot does not require a Marionette connection. Flutter screenshots, ref annotations, and element cropping have been removed.

## Start the capture agent

Prepare a private pairing file using `tool/android_capture.dart`, then start the separate Android instrumentation with Android Studio or Gradle. The [agent setup](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent_android/capture_agent/README.md) describes the SDK requirements and exact steps. Keep the agent running while capturing. Set `CAPTURE_PAIRING` to the private file's path.

The capture command executes no ADB commands: it receives the PNG over an authenticated local TCP connection. Initial APK provisioning and instrumentation startup belong to the Android test environment. Use a different pairing identity and port for each Emulator.

## Save the screen

```sh
marionette-agent screenshot artifacts/system.png --device "$CAPTURE_PAIRING" --json
marionette-agent screenshot artifacts/system.jpg --device "$CAPTURE_PAIRING" --screenshot-format jpeg
```

PNG is the default. JPEG accepts `--screenshot-quality 0..100`, default 90. Create the parent directory first. Omitting the path uses `--screenshot-dir` or a private temporary directory. Existing files are never overwritten.

The result includes `capture.source: "android-uiautomator"`, the paired `device` name, display `0`, `scope: "entire-display"`, `coordinateSpace: "physical-pixels"`, and decoded `width`/`height`. Rotation uses current display pixels without density scaling. Permission dialogs, Photo Picker/file selection, IME, and visible system bars are included. Leave the required UI open while taking the screenshot.

Only an Emulator with one display 0 is supported. `--device` always names the pairing file, and relative paths resolve against the invoking CLI's working directory. There is no discovery, alternate-device selection, or fallback. Authentication, agent loss, malformed output, and deadlines are explicit errors.

Android can hide `FLAG_SECURE` content or reject capture. A successful capture reports `protectedContent: "not-detectable"`; black pixels alone cannot establish protection. Use dummy data and inspect full-screen images before sharing.

## Compare pixels

```sh
marionette-agent diff screenshot --baseline artifacts/system.png --device "$CAPTURE_PAIRING" --output artifacts/diff.png
```

Choose a PNG baseline from the same device and display configuration. Both images must have matching pixel dimensions. Ref/selector crop and `--annotate` are unavailable. See the [capture contract](https://github.com/r0227n/marionette_agent/blob/develop/docs/cli-reference.md#native-android-capture) for limits.

## Record a transition

Device-native recording remains separate from still screenshots. For an iOS Simulator:

```sh
marionette-agent record start artifacts/interaction.mp4 --platform ios --device "$IOS_UDID"
marionette-agent record stop
```

Marionette/Flutter frame recording has also been removed. Use the supported native recording platform for the environment.
