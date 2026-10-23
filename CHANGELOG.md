## 1.0.0

Source release via the `v1.0.0` Git tag and GitHub Release; pub.dev remains disabled.

- Split internal platform services into `marionette_agent_platform_interface` and
  `marionette_agent_{ios,android,macos,web,flutter}`. Remove
  `marionette_agent_util`; migrate app provider imports to
  `package:marionette_agent_flutter/flutter.dart`. CLI commands and extension
  payloads are unchanged.
- Replace external ffmpeg execution with bundled FFmpegKit native assets for
  rendered recordings and FPS conversion. Installations retain native libraries
  in their versioned bundle alongside the executable and guides.
- Align CLI/platform package versions and CLI/MCP version reporting at 1.0.0.
- Add Apache-2.0 licensing, attributed third-party notices in installations,
  security/support guidance, and a documented 1.x compatibility policy.
- Add macOS analysis/test CI, source-to-installed-tester smoke, and release gates.


- Initial version.
- Add a standalone selector-based `wait` command shared with workflow waits.
