# Advanced operation details

[日本語](ja/cli-parity.ja.md) · [Documentation index](README.md)

See the [command reference](https://r0227n.github.io/marionette_agent/en/reference/commands/) for syntax and [app integration](https://r0227n.github.io/marionette_agent/en/getting-started/app-integration/) for provider setup. This supplement describes capability boundaries and edge cases.

<a id="providers"></a>
## What providers observe

Register `registerAgentExtensions()` after binding initialization in debug mode. Auxiliary providers inspect mounted widgets, not the complete Semantics tree or unbuilt lazy-list items. Depth counts observed widget ancestors rather than every internal Flutter element. Visibility uses viewport intersection, Offstage, and center hit testing; it does not guarantee visibility of every pixel.

| Attribute | Observation scope |
| --- | --- |
| inputValue | Controller of a single EditableText; passwords are omitted |
| enabled | Supported TextField/Button/Checkbox/Switch/string Dropdown; readOnly is distinct from disabled |
| checked | Checkbox/Switch or an explicit Semantics boolean; mixed/unavailable is unknown |
| label/placeholder | Explicit Semantics and TextField labelText/hintText |
| role | Explicit Semantics button/textField/link/header mapped to button/textbox/link/heading; not inferred from widget names |

Without a provider, reads may return unknown and actions needing unavailable information return UNSUPPORTED_CAPABILITY. Dblclick and press can use binding APIs; not every additional action requires an auxiliary provider. Display text is never used to guess inputValue, enabled, or checked.

<a id="snapshot"></a>
## Snapshot and typed reads

`--interactive` retains explicitly reported interaction candidates; `--depth` accepts a nonnegative integer. Missing required observation metadata yields exit 6. `--compact` reduces detail while retaining ref/text/inputValue/label. Result options are `{interactive,compact,depth}`. Uniqueness and ref numbering use all observations before filtering; refs omitted from the response are invalid.

`get value` and `is enabled/checked` return `property/known/value`. Preserve unknown rather than substituting false or an empty string. Successful reads retain existing refs.

<a id="find"></a>
## Find matching and positional selection

Key/identifier/role match exactly; text/type/label/placeholder default to case-sensitive substring matching. `--exact` selects exact matching; `--name` applies only to role labels. First/last/nth take one selector and use observation order. Nth is zero-based.

Without an action, find returns `element/index/matchedCount` and does not issue a new ref. Multiple ordinary matches yield AMBIGUOUS_TARGET. Even when first/last/nth selects one element, dispatch requires a unique stable matcher. There is no index or coordinate fallback. Selected attributes are retained and revalidated immediately before dispatch; changes such as key reuse produce STALE_REF/not_sent without acting.

<a id="input"></a>
## Input, keyboard, and gestures

Type focuses and replaces the selection, appending if the selection is invalid. Fill replaces the whole value. Keyboard type/inserttext writes into the focused EditableText through formatters and onChanged. ReadOnly/disabled targets are rejected. Focus supports EditableText or a Focus with an explicit FocusNode.

Press accepts enter/tab/escape/backspace/delete/space, arrows, home/end/pageup/pagedown, letters/digits, and control/shift/alt/meta combinations. Aliases include Ctrl/Cmd/Command/Option/Esc/Return. Keydown/up accepts one key or modifier; duplicate down and up without a matching down are rejected. Close attempts key release, but completion during connection loss is not guaranteed.

Check/uncheck invokes the callback once only when a change is necessary. Select supports enabled string DropdownButton values. Hover sends a synthetic mouse event. Drag validates both targets in the same observation before sending one touch gesture. These operate inside Flutter, not across the host OS.

Scrollintoview calls ensureVisible once for an observed mounted target. It does not keep scrolling to discover unbuilt elements.

<a id="wait-clipboard"></a>
## Waiting and clipboard

A duration wait accepts nonnegative milliseconds, stays within the session queue and overall deadline, and returns `waitedMs` with `requiresSnapshot:false`. A ref wait retains its original selector, checks original attributes for exists, and waits for zero matches for gone. Stale refs are rejected. Explicit null state/poll fields in IPC are rejected rather than treated as defaults. Selector waiting shares the [workflow wait contract](workflow-file-spec.md#wait).

Clipboard operations use the target app’s clipboard, not the CLI host clipboard. Read returns `{text,scope:"target_app"}`, with text possibly null. Copy reads the focused selection and rejects passwords; paste inserts into the focused input. Read/write/copy preserve refs; paste expires them as a mutation.

<a id="diff"></a>
## Cropping and differences

A target screenshot requires a mapped provider, one image, and bounds entirely inside the view. It reobserves before and after capture, does not infer scaling, and returns `cropped:true`. Combining it with annotate is rejected.

Diff snapshot accepts a saved regular envelope or data as its baseline. It ignores ref/reason and ordering but compares duplicate counts, returning `added/removed/changed`. The current observation does not publish or refresh refs. Comparison uses all elements before max-output truncation.

Diff screenshot accepts a single PNG with matching dimensions. A pixel changes when its largest RGBA channel difference exceeds threshold (0–255). Changed pixels are marked red in a PNG saved to a new path. The baseline must be a regular file no larger than 32 MiB. JPEG, multiple images, and baseline overwriting are rejected.

<a id="configuration"></a>
## Config, namespace, and state

Config is an explicitly selected JSON object no larger than 1 MiB, using canonical common-option names. Flags are booleans; other values are strings/integers. Config/help/version and unknown keys are rejected. Relative paths use the caller’s cwd. Precedence follows [runtime details](cli-reference.md#arguments).

Namespace uses the session naming rules and adds a suffix to the runtime path. The final socket path must fit within 80 bytes. State stores only the connection URI, not screens, forms, refs, recordings, or policies. Save writes authenticated URIs into new mode-0600 files without returning the URI on stdout. Load/restore accepts only regular mode-0600 files owned by the current user. The app must still be running with a valid URI. Restore reconnects before the requested command without replaying UI actions.

<a id="batch-policy"></a>
## Batch and action policy

Batch accepts a JSON file or stdin `-` containing 1–100 argument arrays. It parses all syntax before executing sequentially within one session queue. Common options are resolved only on the parent. Allowed commands cover snapshot/get/is/find, input/actions, wait, logs, and clipboard. Connection-lifetime operations, recording, file persistence, differences, and nested batch/workflow are rejected.

Success returns `completed/results`; failures return `completed/failedIndex/results/progressKnown` under `error.details`. Progress may be unknown after connection loss. Execution stops on the first failure, without rollback, replay, or resume.

Policy uses `default:allow|deny` and command-name arrays `allow/deny/confirm`, with precedence deny, confirm, allow. An allow-only list denies unlisted actions. Policies apply to UI mutations, clipboard changes, recording starts, and launch, while allowing observation and close. Click matches tap. Find actions and batch/workflow are checked before execution; invalid find syntax is rejected before policy evaluation.

Policies persist in the session and can be replaced explicitly. They are not an OS authorization boundary. Confirm-actions extends the confirm list. Pending actions return CONFIRMATION_REQUIRED and `confirmationId/command` without displaying input values. One pending action per session remains valid for five minutes within the same connection generation. It cannot be reused after confirm/deny and is discarded on policy change or disconnection. Confirm revalidates target uniqueness/refs; workflow/batch approval covers the whole operation once.

Confirm-interactive prompts on stderr only with a TTY: `y` confirms, anything else denies. Without a TTY it returns the pending error without waiting. ACTION_DENIED and CONFIRMATION_REQUIRED exit 1 with outcome:not_sent.

Recording restart/fps, doctor, and install/upgrade details live in [CLI runtime details](cli-reference.md). Device list returns available iOS Simulators or online Android devices without starting them.
