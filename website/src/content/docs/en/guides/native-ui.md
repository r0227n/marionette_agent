---
title: Native dialogs and photo pickers
description: Operate iOS Simulator and Android system UI through marionette-agent, including permissions and photo selection.
---

Use `native` when a permission dialog or system photo picker covers the Flutter view. These commands operate the selected device's foreground screen without a Flutter VM connection. You can use them in the same session as ordinary Flutter commands.

## Prepare a device

On macOS, iOS native observation and input require working `idb` and `idb_companion` executables on the daemon's `PATH`; screenshots require Xcode's `xcrun simctl`. This supports iOS Simulator, not physical iOS devices. See the [idb installation instructions](https://fbidb.io/docs/installation/). Android requires Android SDK `adb` and an authorized, online emulator or device. No Computer-use integration or app-side native test runner is needed.

```sh
marionette-agent device list --platform ios
marionette-agent device list --platform android
```

Boot the device and launch your debug app using your normal project setup. Always supply the exact iOS UDID or Android serial with `--device`. The command does not choose a default device, boot it, install tools, or silently grant permissions. Keep one operator per device; the daemon serializes native operations on the same device, but separate runtimes and external operators are independent.

## Observe and respond to a permission dialog

Replace `IOS_UDID` with your device ID. Read the actual label and ref before choosing a response; button text varies by OS and language.

```sh
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app native screenshot ./permission.png --platform ios --device IOS_UDID
marionette-agent --session app native tap --text 'Allow' --platform ios --device IOS_UDID
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
```

For Android, replace the platform and serial. Exact `--identifier` selection is useful for permission-controller resource IDs shown by the snapshot.

```sh
marionette-agent --session app native snapshot --platform android --device emulator-5554
marionette-agent --session app native tap @n1 --platform android --device emulator-5554
marionette-agent --session app native screenshot ./android-result.png --platform android --device emulator-5554
```

`@n1` is an example: use a ref returned by your latest native snapshot. Native refs belong to one session and device and are separate from Flutter's `@e` refs. Tap accepts exactly one native ref, exact `--text`, `--identifier`, `--type`, or an explicit `--x`/`--y` pair. Ambiguous labels fail without tapping. Before a ref tap, the CLI rechecks the element's attributes and bounds, then taps its observed center once. A moved or changed element produces `STALE_REF`.

## Select a photo and return to Flutter

Open the picker with an ordinary Flutter `tap` on a target observed in `snapshot`. Use `native snapshot` to inspect the system screen. Some iOS system-hosted photo pickers expose only the application root through idb. A successful native snapshot is therefore not proof that every visible control was discovered; `limitation` explains an empty child observation.

If the desired item has no ref, capture `native screenshot`, inspect the image, and deliberately supply coordinates. There is no automatic fallback from a missing or stale ref to a coordinate tap.

```sh
marionette-agent --session app native screenshot ./picker.png --platform ios --device IOS_UDID
marionette-agent --session app native tap --x 67 --y 379 --platform ios --device IOS_UDID
marionette-agent --session app snapshot
marionette-agent --session app screenshot ./selected-image.png
```

Those coordinates are illustrative and must be replaced using the current screen. iOS uses **screen points**, Android **screen pixels**. The native result includes `coordinateSpace`. An iOS screenshot can have more pixels than screen points: use the native application bounds and image dimensions to scale each axis. For a 1206×2622 image of a 402×874 point screen, divide image coordinates by 3. Do not use Flutter coordinates for native UI or reuse coordinates after rotation. Input coordinates are rounded to integers by the platform tools.

To browse a picker, specify a native finger gesture and observe its result:

```sh
marionette-agent --session app native swipe --start-x 200 --start-y 700 --end-x 200 --end-y 350 --platform ios --device IOS_UDID
marionette-agent --session app native screenshot ./picker-scrolled.png --platform ios --device IOS_UDID
```

After selecting a photo, verify both the Flutter snapshot and image: the picker should close and the app should display the selected content. On iOS Simulator, granting camera permission does not add camera hardware; an app may correctly report that no camera is available.

## Results, evidence, and cleanup

Native snapshots contain `source: native`, platform, device, coordinate space, generation, and normalized elements with bounds. `--json`, `--content-boundaries`, `--max-output`, deadlines, and normal error envelopes apply. Native screenshots include OS overlays and use the same PNG/JPEG options, exclusive file saving, and destination rules as ordinary screenshots. Record the device with `record --platform ios|android` to include native UI; Flutter rendering recordings do not include it.

Native tap/swipe expire native refs for that device across sessions and conservatively expire every Flutter snapshot in the daemon. A Flutter mutation expires native refs in its own session. Observe again after every action. A native screenshot on a different device also expires that session’s prior native refs. Native reads are nonmutating; action policies control tap/swipe under `native`. A post-dispatch failure or timeout returns `outcome: unknown`; inspect the screen before deciding what to do next and never automatically resend.

MCP clients can enable `--tools core,native,record`. The native profile exposes `native_snapshot`, `native_tap`, `native_swipe`, and `native_screenshot` with the `marionette_agent_` prefix. Supply platform and device on each call; native targets accept `@n` refs, text, identifier, or type. Native screenshots also return inline image content. Native commands are not part of batch or workflow v1.

```sh
marionette-agent --session app record stop
marionette-agent --session app close
```

Close releases the session and its refs. Externally launched apps, devices, and idb-managed companions keep their own lifecycle; stop your runner and release your test device separately.
