# Native iOS screenshot feasibility — 2026-10-24

Issue: https://github.com/r0227n/marionette_agent/issues/56

## Decision

Ship an explicit iOS Simulator source using the selected full Xcode's simctl. Keep Flutter capture as the default so tester and existing clients retain their behavior. Do not claim physical-device support: source `ios-device` returns `UNSUPPORTED_CAPABILITY`, with no simctl attempt or Flutter fallback.

## Simulator

The locally inspected Xcode 26.3 (17C529) `simctl io` help supports screenshot output as binary stdout (`-`), explicit internal display, PNG, and mask policies ignored/alpha/black. The implementation fixes `--type=png --display=internal --mask=ignored` and resolves exactly one available, booted iOS UDID from the default device set. It uses full framebuffer dimensions and no Mac window capture. This also avoids temporary native image files and shares the CLI artifact writer for encoding, exclusive paths and cleanup.

The acceptance environment is iPhone 17 Pro, iOS Simulator 26.2, Flutter 3.47.2 / Dart 3.13.2. Landscape UI on this runtime remains sideways in the 1206×2622 portrait framebuffer: returned orientation describes the raster aspect, and pixels are not auto-rotated. Other installed iOS Simulator runtimes may expose the same simctl capability, but the PR's runtime evidence defines the tested combination. Private device sets, external screens, non-iOS Simulator platforms, hardware capture and protected content are outside this implementation's scope. simctl failure is an error, not a reason to recapture from Flutter.

Apple distinguishes device pixels from the host display: its [device screenshot documentation](https://developer.apple.com/documentation/xcode/capturing-screenshots-and-videos-from-devices) describes full device resolution independent of the Mac display. The installed simctl help, rather than the newer Device Hub UI instructions, establishes the actual command options used here.

## Physical devices: feasible separate runner, unsupported here

Apple documents [XCUIScreen](https://developer.apple.com/documentation/xcuiautomation/xcuiscreen) as a device screen and exposes `XCUIScreen.main.screenshot()` for its current UI. The installed Xcode 26.3 XCUIAutomation headers also expose the main screen and screenshot provider. A possible future backend is a dedicated XCTest UI-test runner that obtains PNG data and returns it through a bounded host transport. It must identify the exact physical device and screen independently of any Flutter VM Service.

That is a separate deployment/lifecycle capability, not an extension of simctl. It would require:

- A UI-test runner target, build artifacts and launch/result collection through a compatible Xcode test destination.
- Development signing, a team and a provisioning profile appropriate for the physical device. Apple's [running on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html) documentation requires signing and explains registration, unlocking and trusting the computer.
- Pairing and trust between the device and Mac. Network operation depends on a configured Xcode device connection, not simply a UUID from a Simulator inventory.
- Developer Mode on devices that require it for locally installed development software, with the user's on-device restart/confirmation. See [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). The CLI must never automate this consent.
- An Xcode version supporting the device's installed OS and a runner deployment target compatible with it. An API's availability alone does not validate signing, pairing, permission dialogs or protected-content behavior.

No runner is shipped, and no real-device OS/UI screenshot was tested for this change. Therefore **no physical iOS/iPadOS version is supported or certified**. A future implementation must verify OS-standard UI on actual hardware before advertising support, including timeout/disconnect cleanup and screen identity. Xcode's ability to take device screenshots interactively is not evidence that this CLI can do so.

## Evidence boundary

Use a dedicated Simulator and dummy photos. Capture normal UI, the OS photo authorization dialog, PHPicker, keyboard and both raster orientations with the product CLI; compare the Flutter image, dimensions and returned UDID. Keep commands/results and inspected media with the PR, not raw authenticated runner logs. Unit process fixtures cover stopped/missing/ambiguous targets, multiple booted devices, missing SDK, timeout termination and native acquisition failure without retry. This research note records the design decision; actual acceptance outcomes belong in the verified PR.
