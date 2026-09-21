---
title: Observe, act, verify
description: Use snapshots and refs to keep each interaction grounded in the current screen.
---

Treat an interaction as one loop: observe, select a target, act, and observe the result. This makes divergence between your procedure and the screen visible.

## Read the current screen

```sh
marionette-agent snapshot
marionette-agent snapshot --interactive --compact
marionette-agent snapshot --key tap_button --json
```

A snapshot includes observed attributes such as type, text, key, bounds, and visibility. It is not a complete Widget tree and does not include unbuilt list items. Account for attributes that may be unavailable.

`--interactive` selects interaction candidates, while `--compact` reduces displayed detail. You can also set `--depth`. At most one key, text, type, or identifier filter may be specified.

## Select a target with a ref

A ref is a short reference such as `@e1`, assigned to an actionable element. The following is a syntax example: replace the ref with one returned by your latest snapshot.

```sh
marionette-agent tap @e1
marionette-agent snapshot
```

**After a new snapshot or a UI action, stop using the previous refs.** Refs belong to an observation in one session and also expire on reconnect or disconnect. Do not reuse a ref after an action was sent, even if that action returned an error.

## Verify application state

A completed CLI action still needs an application-level check. This example waits for the expected element and then captures a fresh observation.

```sh
marionette-agent tap --key about_tab
marionette-agent wait --key about_content --timeout 5000
marionette-agent snapshot
```

`wait` repeatedly observes the app. Success does not issue new refs, so take a snapshot before selecting the next action. Waiting for an expected element expresses the purpose of the procedure more clearly than sleeping for a fixed duration.

## Decide what to do after failure

If a timeout or connection loss produces an `unknown` outcome, the app may already have applied the action. Explicitly reconnect and inspect the screen before deciding the next step. The CLI does not automatically resend UI operations.

See [output and errors](/marionette_agent/en/reference/output/) for handling `ok`, `error.code`, and `error.outcome` in JSON.
