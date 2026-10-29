---
title: Compatibility and support
description: The public contracts protected in 1.x and the supported environment.
---

Releases follow semantic versioning for the public 1.x surfaces below.
The current source installation route remains in place; pub.dev is disabled.

## Stable in 1.x

- Documented command names, flags, aliases, accepted arguments, defaults, and
  configuration/environment precedence. Removing or changing their meaning is
  a major-version change. New optional commands/options may arrive in a minor.
- The documented JSON field names, types, null/unknown meaning, and required
  fields. Existing error `code`, `outcome`, and exit-code meanings are preserved.
  Additive optional fields, commands, capabilities, and new error codes can
  arrive in a minor; clients must ignore unknown fields and handle unknown codes
  as failures using the exit category and outcome.
- stdout is the command result and stderr is diagnostics. `--json` emits one
  JSON result for regular commands. The documented `skills` format and MCP
  stdout protocol are separate contracts; do not apply the regular envelope to
  them. Human-readable wording, whitespace, diagnostics, and error message/hint
  prose can change; use JSON rather than parsing text.
- Workflow schema version 1 and app-side Flutter provider's documented public functions and
  service-extension payloads. Required-field/type/meaning changes or removals
  require a major version or an explicit new negotiated schema.

A patch fixes behavior to match the existing contract. A minor adds compatible
capabilities. A major provides migration instructions in CHANGELOG and paired
docs, including affected flags, JSON/errors, and CLI/platform combinations. Security
fixes that must break a contract will explain the exception and migration.

## CLI, daemon, and app versions

Use CLI and `marionette_agent_flutter` from the **same release checkout**. This is
the supported pair; arbitrary cross-release combinations are not promised.
The CLI shares a workspace with `marionette_agent_platform_interface` and the
`marionette_agent_{ios,android,macos,web,flutter}` implementations. The former
`marionette_agent_util` package is removed. App dependencies and provider imports
move to `marionette_agent_flutter` and `package:marionette_agent_flutter/flutter.dart`.
The CLI and default example use `marionette_mcp: ^0.7.0` and
`marionette_flutter: ^0.7.0`. Stock binding covers baseline capabilities; optional
Flutter providers enable additional ones. Missing extensions return
`UNSUPPORTED_CAPABILITY`, not a guessed fallback.

CLI package version, JSON `schemaVersion`, internal IPC `protocolVersion`,
workflow schema version, and app extension version are independent. This release
keeps JSON/workflow version 1, IPC version 7, and app extension version 1. IPC is
internal and may change between 1.x releases; close sessions before upgrading
and start a fresh daemon with the new binary. Do not reuse refs across snapshots,
sessions, reconnections, or mutations.

## Environment and support

Contributors use [Lefthook](https://lefthook.dev/), managed with mise in the root `.mise.toml`, for extension-filtered pre-commit
quality checks on macOS. Install the pinned version and hook after cloning or creating a worktree;
see [Contributing](https://github.com/r0227n/marionette_agent/blob/develop/CONTRIBUTING.md)
and the [release gates](https://github.com/r0227n/marionette_agent/blob/develop/docs/releasing.md#local-gates)
for setup, file selection, and full verification. Documentation checks remain in
CI; release preparation and handoff assume workspace quality was verified locally.

The supported CLI host is macOS; the tested baseline is macOS arm64 with Flutter
3.47.8 and Dart 3.13.7. The SDK constraint is Dart >=3.13.7 <4.0.0, but it is not an
exhaustive guarantee for every SDK combination. Linux/Windows hosts are not
supported. iOS Simulator needs Xcode; Android needs SDK/adb; macOS and Chrome
need their respective app runtimes. Tester covers Flutter UI, not native plugin
or OS behavior. Device recordings have backend-specific permissions and scope;
iOS physical-device recording is not supported.

After release, best-effort fixes target the latest 1.x. No response-time or paid
support SLA is promised. Report ordinary bugs with redacted reproduction,
versions, host, and target runtime through
[GitHub Issues](https://github.com/r0227n/marionette_agent/issues). Security concerns also use this **public** Issues tracker. Post a high-level
redacted summary only; never include secrets, personal information, authentication
tokens, or abuse-enabling details. Request a maintainer-arranged private follow-up
before sharing sensitive reproduction details; no private route is promised.
GitHub private reporting is currently disabled. Reporting and safe-operation
conditions are in [SECURITY.md](https://github.com/r0227n/marionette_agent/blob/develop/SECURITY.md).
Read [output](/marionette_agent/en/reference/output/) and
[troubleshooting](/marionette_agent/en/reference/troubleshooting/) for recovery.

## App binding versions

External apps resolve their own `marionette_flutter` dependency independently of
this CLI. The compatibility matrix covers every published version: 0.1.0, 0.2.0,
0.2.1, 0.2.2, 0.2.3, 0.2.4, 0.3.0, 0.4.0, 0.5.0, 0.6.0, and 0.7.0. Connection,
snapshot, key-based tap, text replacement/clear, logs, and reconnection use each
version's protocol. An app does not need the optional agent provider for these
baseline operations. The optional provider in this checkout requires ^0.7.0.

| Binding     | Additional capabilities and limits                                       |
| ----------- | ------------------------------------------------------------------------ |
| 0.1.0       | Key/text selectors; no type selector or coordinate tap                   |
| 0.2.0–0.3.0 | Type selectors and coordinate taps; Text.data supplies snapshot text     |
| 0.4.0       | Version discovery and custom-extension registry                          |
| 0.5.0       | Swipe and double tap                                                     |
| 0.6.0       | Hardware key input                                                       |
| 0.7.0       | Identifier selectors; explicit visibility requested with compaction:none |

Older bindings cannot execute operations they do not implement; those requests
return `UNSUPPORTED_CAPABILITY` without retrying the action. In versions before
0.4, filling updates the field controller but the upstream binding does not call
`onChanged`; apps relying solely on that callback need a newer binding. Unknown
future releases are not an assertion of tested compatibility.

The repository's `tool/verify_binding_compatibility.py` creates a separate Flutter
app for each exact version and drives the product CLI on an assigned iOS
Simulator. It checks changed screen state, stale refs, missing targets, and
reconnection, and saves sanitized JSON and Simulator screenshots. The shared
workspace lockfile remains at the default 0.7.0 resolution.
