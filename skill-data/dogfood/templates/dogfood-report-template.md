# Dogfood report: {APP_NAME}

| Field | Value |
| --- | --- |
| Date and time zone | {DATE_AND_TIME_ZONE} |
| App revision / build | {APP_REVISION_AND_LOCAL_CHANGES} |
| CLI version / revision | {CLI_VERSION_AND_LOCAL_CHANGES} |
| Flutter / binding / optional provider | {VERSIONS_OR_UNKNOWN} |
| Simulator model / OS / UDID | {DEVICE_DETAILS} |
| Session | {SESSION_NAME} |
| Scope and time budget | {SCOPE_AND_BUDGET} |
| Test data / account role | {NON_SENSITIVE_FIXTURE_DESCRIPTION} |
| Initial state and reset | {HOW_TO_RETURN_TO_THE_START} |

Keep VM Service URIs, credentials, and sensitive input values out of this report.
Describe how to acquire a fresh URI privately when reproducing the run.

## Summary

{Most consequential findings and the limits of this run. Zero findings does not
establish that untested journeys are free of defects.}

Counts below include confirmed findings only.

| Severity | Count |
| --- | --- |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| **Total confirmed** | **0** |

Unconfirmed observations: {COUNT}. Findings with incomplete evidence: {COUNT}.

## Coverage

| Screen / journey / configuration | Status | Evidence, finding, or reason |
| --- | --- | --- |
| {JOURNEY} | tested / partial / skipped / blocked | {LINK_OR_REASON} |

## Findings

<!-- Copy the block for each finding; use unique IDs and actual relative paths.
     Delete unused sample steps and the block itself if there are no findings. -->

### ISSUE-001: {Short title}

| Field | Value |
| --- | --- |
| Severity | critical / high / medium / low |
| Category | visual / functional / ux / content / performance / logs / accessibility |
| Confidence | confirmed / unconfirmed |
| Screen / route | {OBSERVED_SCREEN_AND_NAVIGATION_PATH} |
| Reproduction frequency | {OBSERVED_ATTEMPTS_AND_RESULTS} |
| Evidence status | complete / incomplete — {MISSING_EVIDENCE_AND_REASON} |
| Repro video | [Recording](videos/issue-001-repro.mp4), or N/A with reason |

**Expected:** {Expected behavior and its basis.}

**Actual and impact:** {Observed behavior and how it affects the user.}

**Preconditions and reset:** {Test fixture, account role, starting state, and safe
reset steps. Include how to relaunch/reconnect and obtain fresh refs if needed.}

**Reproduction steps**

1. {Navigate to the starting screen and take a fresh snapshot.}
   ![Starting state](screenshots/issue-001-step-1.png)
2. {Perform the triggering action using the observed key or a newly selected ref.}
   ![After the action](screenshots/issue-001-step-2.png)
3. **Observe:** {The visible failure or incorrect state.}
   ![Result](screenshots/issue-001-result.png)

**CLI evidence**

{Actual sanitized commands/inputs, exit codes, and relevant stdout/stderr excerpts.
Mark omissions, redactions, empty output, and unknown outcomes. For static issues,
keep only the navigation and screenshot evidence that demonstrates the finding.}

## Unconfirmed observations and gaps

{Link unconfirmed finding IDs. Record blocked setup, unavailable capabilities,
failed captures, and untested journeys/configurations without counting them as
confirmed app defects. State what is needed to complete verification.}

## Handoff

{Report path, reset/relaunch instructions, how to acquire a fresh private URI,
and any outstanding recording/session/runner/device cleanup.}

- [ ] Human verification completed
