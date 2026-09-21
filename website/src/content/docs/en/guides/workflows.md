---
title: Turn a procedure into a workflow
description: Describe observations and actions in JSON or YAML, validate them, and execute them in order.
---

Use a named workflow to repeat an interaction you have checked manually. Steps run sequentially within one session, preventing another request from interleaving between them.

## Write a small procedure

Save this as `observe-edit.yaml`, or [download the same file](/marionette_agent/examples/observe-edit.yaml). It targets the example app’s Controls screen.

```yaml
schemaVersion: 1
name: observe-edit
steps:
  - id: before
    action: snapshot
  - id: enter-text
    action: fill
    target: { key: text_input }
    text: { literal: hello }
  - id: after
    action: snapshot
```

Each `id` must be unique within the procedure. Use selectors for `target`; refs issued by snapshots and coordinate targets are not accepted.

## Validate before connecting

```sh
marionette-agent workflow validate observe-edit.yaml --json
marionette-agent workflow schema fill --json
```

`validate` checks file structure and semantic constraints. Element existence and visibility are checked at execution time. `schema` returns the actual input definition bundled with the CLI.

## Run in a connected session

This example uses `docs-demo` from the [quick start](/marionette_agent/en/getting-started/quick-start/). If you closed it, reconnect using the app’s current URI first.

```sh
marionette-agent --session docs-demo workflow run observe-edit.yaml --json
```

The final step takes a snapshot, so the successful result’s `finalSnapshot` lets you inspect the screen after editing. Its refs can be used by subsequent CLI calls as long as no later action has invalidated them.

## Available steps

| Action             | Purpose                                    |
| ------------------ | ------------------------------------------ |
| `snapshot`         | Refresh the observation                    |
| `tap`              | Tap a selector-based target                |
| `fill`             | Replace a field’s text                     |
| `swipe` / `scroll` | Send a directional gesture                 |
| `wait`             | Wait for an element to appear or disappear |

A workflow contains 1–100 steps. Workflow v1 does not include branching, loops, shell execution, workflow includes, or image saving.

## Separate input values

Declare reusable strings under `inputs` with `type: string`, then reference them in step values with `{ input: name }`. Supply values from a JSON or YAML file with `--inputs`. Environment variables and shell expressions are not expanded.

By default, `validate` checks the template. Add `--inputs` or `--check-inputs` to validate bound values as well. `run` always validates input bindings.

## Handle a partial failure

Execution stops at the first failure. Completed operations are not rolled back, and there is no automatic retry or resume. If you received a response, inspect progress in the error details, then observe the actual screen before deciding how to recover.

`--timeout` covers file reading, validation, queueing, and all steps. It is not reset for each step.
