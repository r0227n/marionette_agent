---
title: Read output and errors
description: Use the JSON envelope, process exit codes, and action outcomes to decide what to do next.
---

Use normal text output for interactive reading and `--json` for scripts. Results go to stdout; diagnostics go to stderr.

## The JSON envelope

Regular commands use a shared envelope for success and failure. This is an illustrative success response.

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "demo",
  "data": { "requiresSnapshot": true },
  "error": null
}
```

Check `ok`, then read `data` on success or `error` on failure. Session-independent commands use null for `session`. `requiresSnapshot: true` means you need a fresh observation before making the next decision.

```json
{
  "schemaVersion": 1,
  "ok": false,
  "session": "demo",
  "data": null,
  "error": {
    "code": "STALE_REF",
    "message": "Target changed",
    "hint": "Run snapshot again",
    "outcome": "not_sent"
  }
}
```

Branch on `code` and `outcome` rather than matching the wording of `message`. Use `hint` to identify the next check.

## Understand outcome

| Outcome    | Meaning                                         | Next decision                                   |
| ---------- | ----------------------------------------------- | ----------------------------------------------- |
| `not_sent` | The target operation was not sent               | Correct the arguments, connection, or target    |
| `failed`   | Failure is confirmed                            | Inspect the cause and current application state |
| `unknown`  | The post-dispatch result could not be confirmed | Reconnect and observe the actual state          |

In particular, `unknown` does not mean nothing happened. Reassess the current state before repeating an operation such as a purchase, save, or navigation.

## Process exit codes

| Value | Main category                                                                      |
| ----- | ---------------------------------------------------------------------------------- |
| 0     | Success                                                                            |
| 2     | Arguments: `INVALID_ARGUMENT`                                                      |
| 3     | Connection: `NOT_CONNECTED`, `SESSION_CONFLICT`, `CONNECTION_LOST`                 |
| 4     | Target: `TARGET_NOT_FOUND`, `AMBIGUOUS_TARGET`, `STALE_REF`, `UNRESOLVABLE_TARGET` |
| 5     | Deadline: `TIMEOUT`                                                                |
| 6     | Missing capability: `UNSUPPORTED_CAPABILITY`                                       |
| 1     | Other failures: `BACKEND_ERROR`, `IO_ERROR`, policy denial, and others             |

## Distinguish unknown from empty

Read both `known` and `value` for `is visible`, `is enabled`, and `is checked`. This example represents a state that could not be observed.

```json
{ "known": false, "value": null }
```

It does not mean hidden, disabled, or unchecked. Likewise, distinguish null text from an empty string and null bounds from zero dimensions.

## Command-specific contracts

- `doctor` can return `ok: true` when the diagnostic run completes, yet exit with code 1 because checks failed or remain unknown. Inspect `data.exitCode` and individual checks.
- `skills` uses a separate format for delivering bundled content.
- A running `mcp` process owns stdout for MCP messages. Do not parse it as ordinary CLI JSON.
- `--max-output` is not a size limit on the entire response. Check truncation metadata and ref validity as well.

See [troubleshooting](/marionette_agent/en/reference/troubleshooting/) for recovery procedures.
