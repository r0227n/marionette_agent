# marionette_agent_flutter

Optional debug-only typed observations and interactions for marionette_agent. Add this package to the target Flutter app, initialize `MarionetteBinding`, then call `registerAgentExtensions()` before `runApp`. The Dart CLI remains Flutter-independent.

The provider uses public Widget/State APIs and fixed marionette_flutter 0.6.0. It does not inspect diagnostic strings, disclose password input values, materialize lazy list items, or provide a full Semantics tree. See [the CLI contract](../../docs/ja/cli-parity.ja.md) for supported widgets and limitations.
