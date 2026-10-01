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
- Workflow schema version 1 and app-side util's documented public functions and
  service-extension payloads. Required-field/type/meaning changes or removals
  require a major version or an explicit new negotiated schema.

A patch fixes behavior to match the existing contract. A minor adds compatible
capabilities. A major provides migration instructions in CHANGELOG and paired
docs, including affected flags, JSON/errors, and CLI/util combinations. Security
fixes that must break a contract will explain the exception and migration.

## CLI, daemon, and app versions

Use CLI and `marionette_agent_util` from the **same release checkout**. This is
the supported pair; arbitrary cross-release combinations are not promised.
The current upstream pair is `marionette_mcp: 0.6.0` and
`marionette_flutter: 0.6.0`. Stock binding covers baseline capabilities; optional
util providers enable additional ones. Missing extensions return
`UNSUPPORTED_CAPABILITY`, not a guessed fallback.

CLI package version, JSON `schemaVersion`, internal IPC `protocolVersion`,
workflow schema version, and app extension version are independent. This release
keeps JSON/workflow version 1, IPC version 7, and app extension version 1. IPC is
internal and may change between 1.x releases; close sessions before upgrading
and start a fresh daemon with the new binary. Do not reuse refs across snapshots,
sessions, reconnections, or mutations.

## Environment and support

The supported CLI host is macOS; the tested baseline is macOS arm64 with Flutter
3.47.2 and Dart 3.13.2. The SDK constraint is Dart >=3.13.2 <4.0.0, but it is not an
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
