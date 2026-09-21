---
title: Choose a target
description: Select elements with refs, keys, text, or types while handling ambiguity and stale observations.
---

Snapshot refs are convenient for interactive exploration. A unique app key is useful for repeatable procedures. Every method still requires the target to resolve at the time of the action.

| Selector       | Useful for                            | Constraint                                                                   |
| -------------- | ------------------------------------- | ---------------------------------------------------------------------------- |
| `@e1`          | Operating on an element just observed | Use a ref from the latest snapshot in the same session                       |
| `--key`        | Repeatable procedures and workflows   | Exact match on the observed key                                              |
| `--text`       | Finding displayed wording             | Case-sensitive exact match; not all displayed text is usable for interaction |
| `--type`       | Finding a widget type                 | An action requires a unique target                                           |
| `--identifier` | Identifier selection                  | Unsupported by the interaction matcher in the pinned binding 0.6.0           |

Choose one targeting method accepted by the command. Do not combine a ref, selector, and coordinates.

## Operate using keys

```sh
marionette-agent tap --key tap_button
marionette-agent fill --key text_input 'hello'
marionette-agent get text --key tap_result
```

The selector is resolved against an observation at action time. Zero matches produce `TARGET_NOT_FOUND`; multiple matches produce `AMBIGUOUS_TARGET`. The CLI does not pick an arbitrary candidate.

## Observation filters and action selectors

```sh
marionette-agent snapshot --text 'Save'
marionette-agent get count --text 'Save'
```

These commands tell you whether text matching `Save` was observed. An observed text value does not necessarily match the backend’s interaction matcher. A `get count` result is not proof that an element can be operated on.

A snapshot filter using `--identifier` can narrow observed identifiers. This is separate from support for identifier-based actions.

## Additional search methods

An auxiliary provider enables queries by label, placeholder, role, and other properties. This example uses the example app’s Advanced screen.

```sh
marionette-agent tap --key advanced_tab
marionette-agent find label 'Editable' focus
marionette-agent snapshot
```

`find first`, `find last`, and `find nth` can select by order, but depend more strongly on screen structure. Prefer keys for repeatable procedures to reduce sensitivity to layout changes.

## Use coordinates when needed

```sh
marionette-agent tap --x 120 --y 240
```

Coordinates use Flutter logical pixels. Do not directly substitute physical pixels from a screenshot. Element selection usually preserves intent better when screen sizes and layouts change.
