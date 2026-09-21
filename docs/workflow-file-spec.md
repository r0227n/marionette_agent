# Workflow file reference v1

[日本語](ja/workflow-file-spec.ja.md) · [Documentation index](README.md)

The [workflow guide](https://r0227n.github.io/marionette_agent/en/guides/workflows/) owns getting-started instructions and the downloadable example. This supplement defines the detailed input, execution, and result contract for schemaVersion 1. The public result schema and internal IPC version are separate; see [protocol.dart](../lib/src/protocol/protocol.dart) for the current IPC value.

<a id="validation"></a>
## Local validation and binding

Schema/validate runs without a connection, daemon, or runtime directory. Schema returns bundled JSON Schema Draft 2020-12 without reading external files or the network. Selecting an action returns a standalone schema with that step and necessary `$defs`. Result data is `{workflowSchemaVersion:1,action,schema}`, with null action for the full schema.

Validate defaults to template validation. `--inputs` or `--check-inputs` also validates binding; check-inputs alone uses an empty object. Results contain `workflow/format/stepCount/mode/requiredInputs/inputsValidated`. Mode is template or bound; requiredInputs is the sorted list of required external names. Target existence, uniqueness, visibility, and capability are checked at execution time.

Run always validates binding, so check-inputs is rejected. A previously connected session is required. The CLI validates everything before sending normalized workflow and inputs in one request; the daemon repeats schema and semantic validation.

<a id="files"></a>
## Files, formats, and parsers

Exactly one workflow path is required. Explicit `--format json|yaml` takes precedence; otherwise `.json/.yaml/.yml` determines the format. Inputs follow the same rules using `--inputs-format`. Unknown extensions and stdin `-` require an explicit format. Inputs-format without inputs, and reading both workflow and inputs from stdin, are rejected.

Paths are relative to cwd. URLs, environment variables, command substitution, and includes are not expanded. Non-regular files yield INVALID_ARGUMENT before opening; missing files and read failures yield IO_ERROR. Stdin must be redirected and is read until EOF or the deadline. A leading UTF-8 BOM is accepted; empty or whitespace-only content is rejected. Errors exclude parser source excerpts and file contents.

JSON rejects duplicate keys, including escaped equivalents, trailing commas, nonfinite numbers, and incomplete syntax. YAML uses a single-document 1.2 subset with string keys and null, boolean, finite number, string, sequence, and mapping values. Duplicate keys, tags, anchors, aliases, merge keys, multiple documents, other versions, and unknown directives are rejected. Timestamp-like scalars remain strings. Parsed values are copied into ordinary Maps/Lists without shared nodes.

<a id="document"></a>
## Document and step fields

All objects use closed schemas. Unknown fields and fractional values in integer fields are rejected.

| Document field | Type and constraint |
| --- | --- |
| schemaVersion | Required integer; only 1 |
| name | Required string; `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` |
| description | Optional string; at most 256 Unicode scalars |
| inputs | Optional object; at most 32 definitions |
| steps | Required array; 1–100 entries in execution order |

Every step requires a unique id (`^[A-Za-z][A-Za-z0-9_-]{0,63}$`) and an action.

| Action | Additional fields |
| --- | --- |
| snapshot | None |
| tap | target |
| fill | target, text |
| swipe / scroll | target, direction, optional distance |
| wait | target, state, optional timeoutMs/pollIntervalMs |

Target is an object containing exactly one of key/identifier/text/type with a nonempty string value, matched exactly. Binding 0.6.0 does not support identifier; any such target yields UNSUPPORTED_CAPABILITY before the first UI access. V1 excludes refs, coordinates, snapshot filters, conditionals, loops, parallel steps, shell execution, includes, connection-lifetime operations, screenshots, and logs.

Swipe/scroll direction is left/right/up/down and describes finger movement. Distance is finite and positive, defaulting to 200 logical pixels. Scroll uses the same swipe primitive. Success means gesture completion, not arrival at a particular content position.

<a id="inputs"></a>
## Input definitions

Input names match `^[A-Za-z][A-Za-z0-9_]{0,63}$`. Type is required and must be string. Required/sensitive are optional booleans defaulting to false; default is an optional string. Combining default with required:true or sensitive:true is rejected during template validation.

External values override defaults. Required:true requires an external value even when unreferenced. Optional inputs also need an external value when referenced without a default. Undeclared references fail template validation. Input files map declared names to strings; undeclared keys and null, number, boolean, object, or array values are rejected. Empty strings are valid.

Fill text takes exactly one of these shapes; partial string interpolation is unsupported.

```json
{"literal":"Example value"}
```

```json
{"input":"value"}
```

See [fill-input.json](../samples/workflows/fill-input.json) and [inputs.example.json](../samples/workflows/inputs.example.json) for complete examples.

<a id="wait"></a>
## Wait conditions and deadlines

State is required and must be exists/gone. TimeoutMs is an integer from 1–30,000, default 5,000; pollIntervalMs is 50–1,000, default 100. The first inspect is immediate; subsequent polls wait after the previous inspect completes. Polls never overlap. The step deadline is the earlier of start+timeoutMs and the overall workflow deadline.

Exists succeeds with exactly one match whose visible != false; zero matches or one hidden match keeps waiting. Multiple matches, including hidden ones, yield AMBIGUOUS_TARGET. Gone succeeds with zero matches and keeps waiting for one or more without an ambiguity error. If the sole text match cannot be tied to the backend matcher, both states yield UNRESOLVABLE_TARGET.

Wait sends no UI mutation and does not issue or expire published refs. However, timeout/disconnection during observation or a condition timeout discards the connection and refs with outcome:not_sent. Queue expiration before starting preserves existing state. Standalone wait uses the common timeout and defaults state to exists while sharing these conditions.

<a id="limits"></a>
## Limits

| Subject | Limit |
| --- | --- |
| Workflow input file/stream | 1 MiB UTF-8 |
| Inputs file/stream | 1 MiB UTF-8 |
| Normalized workflow/inputs | 1 MiB each as JSON |
| Object/array nesting | 32 levels |
| Steps / inputs | 100 / 32 |
| Description | 256 Unicode scalars |
| Input value, default, fill literal | 64 KiB UTF-8 each |
| Expanded IPC params / step params | 8 MiB as JSON |
| IPC frame | 64 MiB including newline |

Numbers must be finite. Applicable limits are checked at both CLI and daemon boundaries.

<a id="execution"></a>
## Queue, deadline, and snapshots

The workflow occupies its session queue until completion; other requests cannot interleave between steps. Different sessions can execute concurrently. The overall timeout defaults to 30,000 ms, includes reading/parsing/validation/queue time/all steps, and is not renewed per step. Only IPC receipt of a finalized timeout response gets up to 250 ms of transport grace; the backend deadline is not extended.

Schema errors in later steps, binding, and selector capabilities are checked before any UI access. Each step gets a fresh Execution with the same one-mutation limit as regular commands. Old Futures completing after timeout/disconnection cannot update progress, run subsequent steps, or affect reconnected refs. Execution stops at the first failure without rollback, retry, resume, or automatic replay of the workflow.

Snapshot publishes refs. The last snapshot inside the workflow becomes a candidate; later tap/fill/swipe/scroll discards it, while wait preserves it. Preexisting snapshots and snapshots from failed workflows are not returned. Returned refs remain the latest public snapshot after queue release but expire on another snapshot/mutation/close/reconnect. Reobserve on STALE_REF instead of rerunning the workflow.

<a id="results"></a>
## Success and failure results

Success data contains `workflow/completedSteps/requiresSnapshot`, plus `finalSnapshot` only when still valid. RequiresSnapshot is false with a finalSnapshot and true otherwise. Intermediate results, workflow content, inputs, and resolved fill values are omitted. The [CLI output contract](cli-reference.md#output), including budgets and boundaries, also applies to finalSnapshot.

Failure `error.details` contains `workflow/progressKnown/stepIndex/stepId/action/completedSteps`. StepIndex is one-based; completedSteps counts the confirmed successful prefix. Outcome describes mutation dispatch for the failed step, not whether earlier steps executed.

| Stop condition | Outcome | State |
| --- | --- | --- |
| Validation, not connected, queue expiration | not_sent | Preserve existing state |
| Target/capability resolution failure | not_sent | Preserve connection before mutation |
| Confirmed backend mutation failure | failed | Preserve connection; refs already expired |
| Timeout/disconnection/unclassified failure after mutation dispatch | unknown | Discard connection and refs |
| Timeout/disconnection during snapshot/wait reads, or wait condition timeout | not_sent | Discard connection and refs |

Failures before starting a step have null stepIndex/stepId/action and completedSteps:0. Workflow name is included only when safely available. If no response can be confirmed after dispatch to the daemon, progressKnown:false and outcome:unknown accompany null progress fields. The same applies to an IPC frame overflow after execution, because result delivery is unconfirmed. Never automatically resend UI actions.

<a id="privacy"></a>
## Privacy and implementation references

Workflow content, inputs, resolved params, and fill values are not copied into diagnostics or execution reports. Only constrained workflow names and step IDs appear in results. Sensitive:true forbids embedded defaults; it does not track values or mask snapshots. Values displayed by the app can appear in subsequent snapshots or finalSnapshot. Supply secrets through restricted inputs files or stdin.

- [schema_catalog.dart](../lib/src/workflow/schema_catalog.dart): bundled schema.
- [workflow_loader.dart](../lib/src/cli/workflow_loader.dart): files and parsers.
- [model.dart](../lib/src/workflow/model.dart): semantic validation and binding.
- [workflow_runner.dart](../lib/src/workflow/workflow_runner.dart): execution and progress.
- [wait.dart](../lib/src/commands/wait.dart): conditions.
- [workflow_model_test.dart](../test/workflow_model_test.dart), [workflow_cli_test.dart](../test/workflow_cli_test.dart), [workflow_execution_test.dart](../test/workflow_execution_test.dart): boundary verification.
