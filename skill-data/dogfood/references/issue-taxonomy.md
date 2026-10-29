# Issue taxonomy

Use this reference to plan coverage and classify observed Flutter app findings.
Assign severity by user impact, independently of reproduction confidence.

## Severity

| Severity | Impact |
| --- | --- |
| critical | A core journey is blocked, the app crashes, or user data is lost |
| high | A major feature is unusable and there is no practical workaround |
| medium | A feature has a noticeable problem but a workaround exists |
| low | A minor visual, wording, or polish issue with limited task impact |

Use `confirmed` for a directly evidenced static defect or a safely reproduced
behavioral defect. Use `unconfirmed` for an intermittent or single observation
that cannot yet be reproduced; preserve the attempt count and circumstances.
Report setup and evidence failures separately from app findings.

## Categories and coverage

| Category | What to inspect |
| --- | --- |
| visual | Clipping, overflow, safe areas, keyboard overlap, missing images, contrast, dark/light appearance, animation artifacts |
| functional | Taps and gestures, form validation, search/filter results, state persistence across navigation, duplicate submissions, silent failures |
| ux | Discoverable navigation, back/dismiss paths, loading and action feedback, useful errors and empty states, recovery from interruptions |
| content | Incorrect labels, inconsistent terminology, placeholders, typos, truncation hiding important information |
| performance | Observed launch/transition delays, scrolling jank, repeated pauses, or growing latency during the run |
| logs | Binding-collected exceptions or errors correlated with a user action; include the observed effect and sanitized excerpt |
| accessibility | Labels and control state when exposed, focus order, text scaling, touch targets, and assistive-technology behavior actually exercised |

Treat performance observations as measured or perceived symptoms, not proof of a
memory leak or root cause. Note the device, debug build, capture overhead, and
measurement method. Report missing state as unknown when the binding/provider
does not expose it. A snapshot is neither a full widget tree nor a screen-reader
audit, and logs are not a network inspector.

## Exploration checklist

Track each selected journey as tested, partial, skipped, or blocked, with a reason
and an evidence/finding link where relevant.

1. Map the main screens and complete the primary user journey with disposable data.
2. Inspect initial, empty, loading, successful, and error states that are reachable
   within the agreed scope.
3. Exercise controls and navigation, including returning from a detail screen,
   dismissing a modal, and recovering from validation errors.
4. Test forms with representative valid, empty, invalid, and boundary inputs.
   Check keyboard obstruction and whether values survive navigation as expected.
5. Observe scrolling and paging in the correct region. Check the final content
   and state rather than inferring success from the gesture response.
6. Compare baseline logs with those after suspicious actions, and capture visible
   symptoms alongside relevant diagnostics.
7. When in scope and available, vary orientation, appearance, text size, device
   size, and authentication role. Record untested configurations; do not claim
   coverage from a single Simulator configuration.
8. Check recovery/reset paths before reproducing a mutation. Keep irreversible or
   externally visible operations within the user's explicit authorization.
