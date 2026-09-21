---
title: Troubleshooting
description: Diagnose connection failures, stale refs, ambiguous targets, missing providers, and capture errors.
---

Identify whether the failure concerns the environment, connection, target, or post-action result. Record the error `code` and `outcome`. If execution is uncertain, inspect the screen before resending an operation.

## Inspect the local environment

```sh
marionette-agent doctor --json
marionette-agent doctor --quick --json
```

A regular doctor run reads the environment; it does not install SDKs or boot Simulators. Inspect each check’s `status`, `reason`, and `nextStep`. `--quick` limits checks to the host, runtime, and daemon.

To probe a running app, set `VM_URI` to the URI from its current run.

```sh
marionette-agent doctor --probe-uri "$VM_URI" --json
```

The probe uses an independent connection and does not change normal session refs. Finding the binding registration does not guarantee every operation will succeed.

## Connection problems

| Symptom            | What to check                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------------- |
| `NOT_CONNECTED`    | Are you using the same session name? Have you connected or launched it?                              |
| `CONNECTION_LOST`  | Is the app or Flutter runner still running? Is the URI current after hot restart?                    |
| `SESSION_CONFLICT` | Does another session own the URI? Is the launch project already managed?                             |
| Launch timeout     | Is the deadline long enough for the initial build and device startup? Are app dependencies resolved? |

When reconnecting to an external app, specify its current URI and the intended session, then take a new snapshot. Check that your URI file is current before repeating the procedure.

## Target selection problems

**`STALE_REF`**: Take a fresh snapshot and use a ref returned by it. Do not guess numbers or reuse refs from another session.

**`AMBIGUOUS_TARGET`**: Multiple candidates share the text or type. Inspect them with snapshot or get count, then use a unique key.

**`TARGET_NOT_FOUND`**: Check that the target screen is displayed and the key is correct. Scroll unbuilt lazy-list items into an observable state first.

**`UNRESOLVABLE_TARGET`**: The observed display text cannot safely be associated with a supported interaction target. Use a supported selector such as a key.

## Missing capabilities

For `UNSUPPORTED_CAPABILITY`, check binding and auxiliary-provider registration. Identifier-based actions are unsupported by the pinned binding 0.6.0. Annotations need a mapped screenshot provider; typed state and additional input need their corresponding Flutter extensions.

## Capture failures

- Check that the parent directory exists and is writable, and choose a filename that does not already exist.
- Select `--screenshot-format jpeg` explicitly when saving `.jpg` files.
- Prepare a connected session and ffmpeg for recording Flutter rendering.
- Use the correct UDID, serial, or display number for device capture and check required screen-recording permissions.
- Allow enough time for stop or close; do not terminate the process while it finalizes video.

## Report a problem

Include the CLI version, source commit, host, Flutter SDK, execution environment, a command with credentials removed, error `code` and `outcome`, and the before/after state. Use `--debug` to investigate processing stages. Remove URIs, input values, and private app data from shared logs and images.

Check [GitHub issues](https://github.com/r0227n/marionette_agent/issues) for existing reports.
