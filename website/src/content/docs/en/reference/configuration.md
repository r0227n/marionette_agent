---
title: Options and configuration
description: Configure common CLI options, environment variables, config files, and action policies.
---

Use CLI options for one-off settings and an explicit JSON file for repeatable defaults. Session and timeout also support environment variables.

## Common options

| Option                          | Meaning and default                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------ |
| `--session NAME`                | Session name; defaults to `default`; `--session-name` is an alias                    |
| `--timeout MS`                  | Total deadline including file reading, queueing, and execution; defaults to 30,000ms |
| `--json`                        | Return a JSON result                                                                 |
| `--debug`                       | Write diagnostic stages to stderr                                                    |
| `--config PATH`                 | JSON defaults for common options                                                     |
| `--namespace NAME`              | Isolate daemon runtime by name                                                       |
| `--idle-timeout DURATION`       | Daemon startup idle timeout; defaults to 1h; 0 disables it                           |
| `--content-boundaries`          | Mark app-provided data in snapshot and logs                                          |
| `--max-output N`                | Character budget for complete snapshot or log entries                                |
| `--screenshot-format png\|jpeg` | Image format; defaults to png                                                        |
| `--screenshot-quality N`        | JPEG quality from 0 to 100; defaults to 90                                           |
| `--screenshot-dir PATH`         | Existing destination directory when image path is omitted                            |
| `--restore PATH`                | Connect to a saved URI before executing                                              |
| `--action-policy PATH`          | JSON allow, deny, and confirm policy                                                 |
| `--confirm-actions LIST`        | Add comma-separated command names requiring confirmation                             |
| `--confirm-interactive`         | Request confirmation on a TTY                                                        |

Duplicate options are argument errors. Use positive integer milliseconds for `--timeout`; `--idle-timeout` also accepts values such as `10s`, `3m`, or `1h`. An idle setting that differs from the running daemon is rejected before dispatch.

## Config files and precedence

Save this as `agent.config.json`.

```json
{
  "session": "demo",
  "timeout": 10000,
  "json": true
}
```

```sh
marionette-agent --config agent.config.json snapshot
```

Precedence is explicit CLI → session/timeout environment variables → explicit config → defaults. Config keys use canonical option names. Flags take booleans; other options take strings or integers. Unknown keys are rejected. Relative paths resolve from the CLI’s working directory.

| Environment variable           | Purpose                                            |
| ------------------------------ | -------------------------------------------------- |
| `MARIONETTE_AGENT_SESSION`     | Default session name                               |
| `MARIONETTE_AGENT_TIMEOUT_MS`  | Default timeout                                    |
| `MARIONETTE_AGENT_RUNTIME_DIR` | Private runtime directory                          |
| `MARIONETTE_AGENT_SKILLS_DIR`  | Override bundled Skills with an existing directory |

Empty session and timeout environment variables are not treated as unset. A selected empty value is an argument error. Values overridden by explicit CLI options are not range-validated.

## Output budgets and boundaries

```sh
marionette-agent snapshot --json --content-boundaries --max-output 4000
```

`--max-output` counts Unicode code points and retains complete entries from the beginning. It does not limit the JSON envelope or image byte size. Check `truncated`, `originalCount`, and `omittedCount`; omitted refs cannot be used for actions.

`--content-boundaries` identifies app strings as observed data. It does not sanitize their contents.

## Control actions

This policy denies drag and requires confirmation for tap.

```json
{
  "default": "allow",
  "deny": ["drag"],
  "confirm": ["tap"]
}
```

Load it with `--action-policy` to retain it in the session. Precedence is deny → confirm → allow. A pending operation returns `CONFIRMATION_REQUIRED` and an ID; resolve it with `confirm ID` or `deny ID`. One pending operation is retained for five minutes within the same connection generation.

A policy can be explicitly replaced, so it is not a substitute for OS authorization. MCP startup does not accept `--confirm-interactive` or `--restore`.

## Save a connection destination

`state save` writes only connection information, including the authenticated URI, to a new file with mode 0600. It does not save the app screen, input values, refs, or recordings. `state load` and `--restore` require a regular 0600 file owned by the current user. Obtain a new URI if the app restarts and its URI changes.
