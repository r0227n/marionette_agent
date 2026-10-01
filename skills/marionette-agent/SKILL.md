---
name: marionette-agent
description: Operate Marionette-enabled Flutter apps with the marionette-agent CLI. Use for inspecting app state, tapping or filling controls, swiping, capturing screenshots, or verifying Flutter behavior on iOS Simulator.
allowed-tools: Bash(marionette-agent:*), Bash(dart:*)
hidden: true
---

# marionette-agent

A Dart CLI for Flutter app automation through VM Service, with named sessions,
snapshots, and compact `@eN` element references.

## Start here

Load the installed CLI's workflow guide before operating an app:

```sh
marionette-agent skills get core
marionette-agent skills get core --full
```

This discovery stub points to the versioned guides distributed with the CLI.
The second command also includes command references and templates.

The app must already be running in debug mode with `MarionetteBinding` initialized
and a reachable VM Service URI. To install from a prepared repository checkout,
run its `bin/marionette_agent.dart` entrypoint with
`install <existing-bin-directory>`. Add that directory to PATH and retain the
adjacent hidden asset directory printed by `skills path`.

## Simulator verification

For runtime acceptance checks and screenshot evidence, load:

```sh
marionette-agent skills get simulator-verify
marionette-agent skills get simulator-verify --full
```

Use `marionette-agent skills list` to discover the installed guides, and
`marionette-agent skills path <name>` to locate their supplementary files.

`skills` reads local files; it does not download or install skills into an agent's
configuration directory. Install discovery stubs separately if your agent needs them.
