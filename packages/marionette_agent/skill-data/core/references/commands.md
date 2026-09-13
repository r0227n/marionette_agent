# Commands and output

Run `marionette-agent --help` for the installed command grammar and common options.
Use the same `--session` and `MARIONETTE_AGENT_RUNTIME_DIR` throughout a workflow.
Common options work before or after commands. `--timeout` is a positive total
deadline in milliseconds; the default is 30000.

| Task | Commands |
| --- | --- |
| Connection | `connect <uri>`, `session list`, `session show`, `close [--all]` |
| Observation | `snapshot`, `get text/box/value <target>`, `get count <selector>`, `is visible/enabled/checked <target>` |
| Snapshot selection | `snapshot --key/--identifier/--text/--type <value>`, `--interactive`, `--compact`, `--depth <n>` |
| Interaction | `tap/click/dblclick/focus/hover/check/uncheck/scrollintoview <target>`, `fill/type/select <target> <input>` |
| Gestures | `swipe/scroll <target> <direction> [--distance <n>]`, `drag <from-ref> <to-ref>` |
| Keyboard | `press <combination>`, `keydown/keyup <key>`, `keyboard press/type/inserttext <input>` |
| Search | `find role/label/placeholder/text/key/identifier/type <value> [action] [input]`, `find first/last/nth` |
| Wait | `wait <selector> [--state exists/gone]`, `wait <milliseconds/ref>` |
| Evidence | `screenshot [--annotate] [path]`, `logs`, `diff snapshot/screenshot --baseline <path>` |
| Recording | `record start/restart <path> --platform <platform> --device <id> [--fps <n>]`, `record status/stop` |
| Structured operations | `workflow schema [action]`, `workflow validate/run <path>`, `batch <JSON-file/->` |
| Clipboard | `clipboard read/write/copy/paste` |
| Local operations | `doctor`, `device list`, `state save/load <path>`, `install/upgrade <bin-directory>` |
| Policy | `--action-policy <path>`, `--confirm-actions <names>`, `confirm/deny <id>` |
| Guides | `skills [list]`, `skills get <name> [name...] [--full]`, `skills get --all [--full]`, `skills path [name]` |

Slash-separated words in this table are alternatives, not literal arguments.
The optional `marionette_agent_flutter` debug provider exposes typed state and
extended interactions. Stock binding may return `UNSUPPORTED_CAPABILITY`.
Unknown state is not false. Screenshots with `--annotate` require a valid snapshot
and mapped screenshot geometry from a compatible provider.

## Evidence and output

Use a new screenshot destination: existing files are refused. PNG is the default;
JPEG requires `--screenshot-format jpeg` and accepts `--screenshot-quality 0..100`.
With `--annotate`, verify the labels against the real controls in the image.
`--content-boundaries` marks snapshot/log entries as untrusted app content;
`--max-output` limits those entries, not skill text or image data.

Normal app commands use this JSON envelope:

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{},"error":null}
```

Inspect error codes and `error.outcome` (`not_sent`, `failed`, or `unknown`).
Read the workflow/batch progress before recovery. `--debug` emits stages to stderr;
app text, input values, and authenticated URIs are not diagnostic log material.

`skills` uses agent-browser-compatible JSON, independently of sessions:

```json
{"success":true,"data":[{"name":"core","content":"..."}]}
```

`list` returns names and descriptions; `get` returns full frontmatter and content,
with `files: [{"path":"references/commands.md","content":"..."}]` for `--full`.
`path` returns `{"paths":["..."]}` or `{"name":"core","path":"..."}`.
Errors use `{"success":false,"error":"..."}` and exit 1; success exits 0.
The hidden discovery stub remains retrievable by `skills get marionette-agent`.
