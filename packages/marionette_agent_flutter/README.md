# marionette_agent_flutter

Optional debug-only typed observations and interactions for marionette_agent. Add this package to the target Flutter app, initialize `MarionetteBinding`, then call `registerAgentExtensions()` before `runApp`. The Dart CLI remains Flutter-independent.

The provider uses public Widget/State APIs and fixed marionette_flutter 0.6.0. It does not inspect diagnostic strings, disclose password input values, materialize lazy list items, or provide a full Semantics tree. See [the CLI contract](../../docs/ja/cli-parity.ja.md) for supported widgets and limitations.

## Deliberately hidden native views

Call `enableHeadlessRendering()` after initializing the binding and before `runApp` only when explicitly launching a hidden debug app. It requests forced frames every 16ms while the OS reports hidden/paused/detached, without changing lifecycle state or notifications. Visible states and the returned disposal callback stop those requests. Release builds do nothing.

This does not hide a window or start a native engine. The macOS [headless guide](../../docs/ja/headless.ja.md) supplies both the native window setup and this opt-in. Native plugins use the actual macOS environment; this is not a Flutter tester platform simulation. The extra frames consume resources even while the application is hidden; use this helper only for deliberate debug automation.
