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
