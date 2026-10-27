## Unreleased

- Replace Android ADB screenshot capture with a separately started UI Automator instrumentation and authenticated TCP pairing. `--device` now names a private pairing file rather than an ADB serial.
- Remove Marionette/Flutter screenshots, mapped screenshot providers, ref annotations, element crop, and Marionette frame recording. Native recordings remain available. These are breaking development changes; use the UI Automator setup and migration instructions in the capture guide before upgrading.
- Require pairing for CLI/MCP/workflow screenshots and native image differences; internal IPC advances to 9. Close the old daemon using the old CLI first.

## 1.0.0

Source release via the `v1.0.0` Git tag and GitHub Release; pub.dev remains disabled.

- Align CLI/util package versions and CLI/MCP version reporting at 1.0.0.
- Add Apache-2.0 licensing, attributed third-party notices in installations,
  security/support guidance, and a documented 1.x compatibility policy.
- Add macOS analysis/test CI, source-to-installed-tester smoke, and release gates.


- Initial version.
- Add a standalone selector-based `wait` command shared with workflow waits.
