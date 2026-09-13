---
name: core
description: Control a running Flutter app with marionette-agent using connect, snapshot, one operation, and fresh observation. Read for element targeting, session lifecycle, and failure recovery.
---

# Flutter app automation

## Connect and observe

Use a debug Flutter app with `marionette_flutter` binding initialized. Obtain its
VM Service URI from the app runner's private URI file. HTTP(S) and WS(S) forms are
accepted. Keep the URI and raw runner logs private; disable shell tracing.

```sh
marionette-agent --session demo connect "$VM_URI"
marionette-agent --session demo snapshot
```

Read the returned elements and choose one visible, unambiguous target. Prefer a
stable key from the app or an `@eN` reference from this session's latest snapshot.
The following `@e1` is illustrative: substitute a reference actually returned.

```sh
marionette-agent --session demo tap @e1
marionette-agent --session demo snapshot
```

After each operation, confirm the state change in a fresh snapshot and, when
checking visible behavior, a screenshot. A successful gesture response does not
prove that the intended page or state was reached.

## Targeting and input

Choose one target mode: a ref, one selector (`--key`, `--identifier`, `--text`,
`--type`), or coordinates supported by that command. Multiple matches fail;
the CLI does not guess. Availability of identifier and typed state depends on
the app's registered provider.

```sh
marionette-agent --session demo fill --key text_input 'hello'
marionette-agent --session demo snapshot
marionette-agent --session demo fill --key text_input ''
marionette-agent --session demo snapshot
marionette-agent --session demo swipe --key page_view left --distance 200
marionette-agent --session demo snapshot
```

`fill` replaces the entire value; empty text clears it. Use `--` before literal
input beginning with a dash. Swipe and scroll directions describe finger motion.
Coordinates use Flutter logical pixels, not screenshot pixels.

## Failures and lifetime

UI operations are sent at most once. A stale ref needs a fresh snapshot; an
ambiguous target needs a more precise selector. After a connection loss or timeout,
read the reported outcome. For `unknown`, reconnect and observe the actual state
before deciding whether another operation is appropriate. Never replay a failed
workflow or batch automatically: earlier steps may already have changed the app.

Keep one session per independent app connection. Refs belong to their session and
observation; operations invalidate them. Finish with:

```sh
marionette-agent --session demo close
```

`close` finalizes that session's recording and releases its connection. The app
runner must be stopped separately. `close --all` affects every session in the
selected runtime, so use it only when you own all of them.

## Read more when needed

- For command groups, output envelopes, and optional providers, read
  [references/commands.md](references/commands.md).
- For a reusable connect/observe/cleanup shell example, read
  [templates/observe-session.sh](templates/observe-session.sh).
- For real Simulator verification, load `marionette-agent skills get simulator-verify`.

Locate these files with `marionette-agent skills path core`, or include them in
the command output with `marionette-agent skills get core --full`.
