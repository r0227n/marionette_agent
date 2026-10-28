# UI Automator capture agent

This Android instrumentation calls `UiDevice.takeScreenshot(File)` directly. The Dart capture backend and this agent execute no ADB commands, shell capture, forwarding, or Flutter screenshot extensions. Android Studio/Gradle provide the separate Android test installation and instrumentation startup environment; that environment still uses Android debugging transport internally.

1. Use Java 17+ and Android SDK platform 36. Prepare a private pairing from the repository root:

   ```sh
   dart run tool/android_capture.dart prepare capture-pairing.json emulator-test 37657
   ```

2. Set `MARIONETTE_CAPTURE_PAIRING` to the absolute path of that mode-0600 file in the environment of Android Studio or Gradle. Open this directory in Android Studio and run `CaptureAgentTest.serveCaptures` on the chosen Emulator. Alternatively, use `./gradlew connectedDebugAndroidTest` (pinned Gradle 9.3.1) and `ANDROID_SERIAL` selecting that Emulator. These are provisioning/test-runner steps; the screenshot command performs neither step.
3. Leave the instrumentation running and take images from the repository root:

   ```sh
   dart run bin/marionette_agent.dart screenshot system.png --source android-emulator --device capture-pairing.json
   dart run bin/marionette_agent.dart screenshot system.jpg --source android-emulator --device capture-pairing.json --screenshot-format jpeg
   ```

4. Stop only this agent with `dart run tool/android_capture.dart stop capture-pairing.json`, or stop its test in Android Studio. The agent also ends after 30 minutes. Delete the pairing file when finished.

The Emulator connects out to host loopback through `10.0.2.2`; no port forwarding is needed. The CLI listens only during a capture and binds 127.0.0.1 on the paired port. Each request uses a fresh nonce and mutual HMAC-SHA256 proof; the secret is never transmitted. Use a distinct file, identity, and port per Emulator. The logical device name identifies the paired agent, not an ADB serial. Pairing is local development trust, not remote-device attestation.

Protocol v1 frames JSON as a four-byte unsigned big-endian length plus UTF-8 (at most 8192 bytes). Host challenge is `{version,nonce}`; agent hello is `{version,device,proof,emulator,displays}`. Proof inputs are `agent:<nonce>` and `host:<nonce>:<command>`. Commands are `capture` and `stop`. Capture responds `{ok:true,length}` followed by that many PNG bytes (at most 32 MiB), or `{ok:false,code}`. No received capture is automatically replayed. File staging is private target-app cache and is removed in finally.

Only Emulator hardware ranchu/goldfish with a single display 0 is supported. The agent checks display topology before capture. Visible system UI is included. Android may hide FLAG_SECURE content; a successful black image cannot establish its protection status. Neither security flags nor debugging authorization are changed.

Pinned AndroidX UI Automator 2.3.0, AndroidX runner 1.5.1 and JUnit 4.13.2 are resolved by Gradle. See [UiDevice](https://developer.android.com/reference/androidx/test/uiautomator/UiDevice) and [Emulator networking](https://developer.android.com/studio/run/emulator-networking-address).
