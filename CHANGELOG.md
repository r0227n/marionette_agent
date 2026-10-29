## 1.1.0

This release adds native UI automation and OS-level capture across supported
platforms. **It intentionally includes breaking changes despite the minor version
number, as an exception to the documented 1.x compatibility policy.** Review the
migration steps below before upgrading. pub.dev publication remains disabled.

### Added and improved

- Observe Flutter controls and native iOS Simulator/Android system UI in one
  session. Bind an explicit device with `session bind`, then use `snapshot`,
  `tap`, and `swipe` for permission dialogs and photo pickers through configured
  XCUITest/UI Automator runners. Native-only sessions do not need a Flutter VM
  connection; mixed snapshots distinguish Flutter `@e` and native `@n` refs.
- Capture OS screenshots, including visible system dialogs, on iOS Simulator
  and macOS through XCTest/XCUIScreen, and on Android Emulator through a paired
  UI Automator capture agent. CLI, MCP, workflows, and screenshot diffs use the
  same capture routes, with PNG/JPEG output and capture metadata.
- Replace recording backends with XCUIScreen sampling on iOS Simulator,
  UI Automator sampling on Android Emulator, ScreenCaptureKit on macOS, and
  Chromium CDP viewport capture on Web, including headless Chrome. Bundle the
  native video encoding dependencies. iOS/Android/Web produce silent H.264 MP4;
  macOS produces silent H.264 MOV.
- Support published `marionette_flutter` bindings from 0.1.0 through 0.7.0,
  respecting each version's capabilities. Update default `marionette_mcp` and
  `marionette_flutter` dependencies to ^0.7.0 and add a per-version Simulator
  compatibility verification tool.
- Add a Flutter dogfood skill, issue taxonomy, and evidence-based report template.
- Split platform implementations into dedicated workspace packages and pin the
  development toolchain to Flutter 3.47.8 and Dart 3.13.7. Move macOS quality
  checks to Lefthook pre-commit hooks; documentation checks remain in CI.

### Fixes

- Reject expired process requests before spawning a child, close unused stdin,
  and handle output-stream failures without leaving child processes running.
- Continue session, capture, and daemon cleanup when individual cleanup steps
  fail, including retiring IPC files and releasing the daemon lifetime lock.

### Breaking changes and migration

- **App integration:** `marionette_agent_util` is removed. Replace the app's
  dependency with `marionette_agent_flutter` from the same release checkout and
  change provider imports to `package:marionette_agent_flutter/flutter.dart`.
  The optional provider requires `marionette_flutter: ^0.7.0`; apps using only
  stock binding capabilities can retain a supported older binding. Update the
  SDK to Dart >=3.13.7 <4.0.0 (the pinned Flutter SDK supplies Dart 3.13.7).
- **Screenshots:** the Flutter/Marionette screenshot route, ref/selector crops,
  `--annotate`, and the mapped screenshot provider are removed. Replace plain
  `screenshot` calls with an explicit OS target:

  ```sh
  marionette-agent --timeout 120000 screenshot artifacts/ios.png --device "$SIMULATOR_UDID"
  marionette-agent screenshot artifacts/android.png --source android-emulator --device "$CAPTURE_PAIRING"
  marionette-agent --timeout 120000 screenshot artifacts/macos.png --source macos --display 1
  ```

  Use an exact booted Simulator UDID, a private Android capture-agent pairing
  file, or an explicit macOS display number. macOS uses `display`, not `device`.
  Prepare the Android agent separately; Apple capture requires full Xcode and
  macOS capture requires Screen Recording permission. Set the same target fields
  in MCP/workflow screenshot requests and screenshot diffs. Regenerate diff
  baselines from the same OS source and dimensions; Flutter ref geometry no
  longer maps to screenshots. There is no replacement for built-in cropping or
  ref annotation, and physical iOS devices remain unsupported.
- **Recording:** `--platform flutter` and Flutter tester recording are removed.
  Select `ios`, `android`, `macos`, or `web` and provide an explicit device and
  a new output path. Android now takes the capture pairing file as `--device`.
  Web now takes a loopback page CDP endpoint directly, without the old
  `display:N@` prefix, and saves `.mp4` rather than `.mov`:

  ```sh
  marionette-agent --timeout 120000 record start artifacts/ios.mp4 --platform ios --device "$SIMULATOR_UDID"
  marionette-agent record stop
  marionette-agent record start artifacts/web.mp4 --platform web --device "$CDP_PAGE_WS_URL"
  marionette-agent record stop
  ```

  Web captures the page viewport rather than the Mac display. macOS recording
  requires macOS 15+, Xcode, and Screen Recording permission. On iOS/Android/Web,
  `--fps` controls sampling delay rather than guaranteeing a video frame rate.
  Recordings need no Flutter connection and do not fall back to Flutter capture.
- **Native UI commands:** replace the former native command/tools/profile with
  `session bind --platform ios|android --device <id>` and shared `snapshot`,
  `tap`, and `swipe` commands. Configure and start the platform's native runner
  first. Use `snapshot --source native` and current `@n` refs; native selectors
  and coordinates require `--source native`. MCP uses the `core` profile and
  `marionette_agent_session_bind`, `marionette_agent_snapshot`,
  `marionette_agent_tap`, and `marionette_agent_swipe`. Workflow v1 mutation
  selectors remain Flutter-only. Never reuse refs from an earlier snapshot.
- **Daemon upgrade:** close existing sessions before replacing the CLI and start
  a fresh daemon. Internal IPC is now version 9; JSON schema and workflow schema
  remain version 1. Schema version 1 does not remove the need to migrate the
  affected screenshot and native-tool requests above.

For setup and full contracts, see the
[capture guide](website/src/content/docs/en/guides/capture.md),
[native UI guide](website/src/content/docs/en/guides/native-ui.md), and
[compatibility reference](website/src/content/docs/en/reference/compatibility.md).

## 1.0.1

Source release via the `v1.0.1` Git tag and GitHub Release; pub.dev remains disabled.

- Fix legacy `marionette_flutter` 0.6.0 inspection failing with `Invalid visibility`
  when Flutter diagnostic properties such as `enabled: "true"` collide with typed
  state fields. Preserve the binding's explicit protocol attributes and retain
  strict validation for typed providers.
- Add regression coverage for diagnostic property collisions, malformed legacy
  attributes, and typed-provider validation. No app-side binding upgrade is required.
- Add reviewed Git-flow release preparation and handoff automation; publication
  remains a separately authorized action.

## 1.0.0

Source release via the `v1.0.0` Git tag and GitHub Release; pub.dev remains disabled.

- Align CLI/util package versions and CLI/MCP version reporting at 1.0.0.
- Add Apache-2.0 licensing, attributed third-party notices in installations,
  security/support guidance, and a documented 1.x compatibility policy.
- Add macOS analysis/test CI, source-to-installed-tester smoke, and release gates.


- Initial version.
- Add a standalone selector-based `wait` command shared with workflow waits.
