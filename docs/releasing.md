# Release preparation and distribution

[日本語](ja/releasing.ja.md)

## Current route and scope

Released versions use immutable Git tags and GitHub Releases with source archives.
For 1.0.1, select `v1.0.1`, resolve the committed lockfile, and compile locally.
Keep `publish_to: none` in CLI/util/example; global Pub activation and pub.dev
publication are not supported. Development installations may select a reviewed
`develop` commit and must record that SHA instead of assuming release behavior.

The installer distributes the native executable and its matching sibling
`.marionette-agent-*` directory with Skills and LICENSE/NOTICE/THIRD_PARTY_NOTICES.
Retain all of these when moving or redistributing a binary. Upgrades preserve old
bundles; remove only those no installed executable uses. App-side util is consumed
from the same checkout. No prebuilt multi-platform assets are promised.

## Licensing audit

Original project code/docs use Apache-2.0, following
[leancodepl/marionette_mcp's LICENSE](https://github.com/leancodepl/marionette_mcp/blob/main/LICENSE)
(blob `261eeb9e9f8b2b4b0d119366dda99c6fd7d35c64`, checked 2026-10-01).
NOTICE names this project's contributors without appropriating upstream ownership.
The dependency files remain verbatim in THIRD_PARTY_NOTICES.txt. The generator
walks **production** dependencies of CLI/util/example, including app-side Flutter/engine
notices and the Dart runtime. It fails on missing licenses; `--check` rejects
stale notices. It deliberately overincludes the declared closure instead of
claiming every package is linked into the AOT executable.

Runtime dependencies include Apache-2.0 Marionette, MIT image/archive libraries,
and BSD Dart/Flutter packages. Preserve original notices. Resolve the committed
lockfile with Flutter 3.47.2 before generating. Dependency/SDK changes require a
fresh audit, including embedded assets and nested third-party notices in packages.
The generated file is not an automated legal compatibility verdict.

The externally managed development skills listed in skills-lock.json come from
[mattpocock/skills](https://github.com/mattpocock/skills) under MIT; their original
notice is retained in `third_party/mattpocock-skills-LICENSE` (upstream LICENSE
blob `f1dd2c09108dde1a5f56097cee8461b3ea834499`). They are not installed with the CLI.
The bundled Skills are this project's material. The example contains Flutter
scaffold/icons; retain Flutter/engine and cupertino_icons notices if distributing
an example build. Website build tooling is not included in the CLI binary;
redistribution of generated sites or new bundled assets needs its own scope audit.

## Local gates

Use the pinned baseline Flutter 3.47.2 / Dart 3.13.2 on macOS. Run from the root,
then the indicated member directories. `--concurrency=1` avoids process-heavy
test contention. The CLI test runner's `--timeout=2m` includes cold child-process
JIT startup on hosted macOS; product deadlines and explicit test timeouts still
apply. The tester smoke builds no native app and boots no Simulator.

Install ffmpeg and ffprobe before these gates. Two real MP4 encoding tests skip
when either tool is absent; both must execute for release verification. CI
provides the tools on its macOS runner. They are not included in release assets.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed bin lib test tool integration_test packages/marionette_agent_util/lib packages/marionette_agent_util/test packages/marionette_agent_util/flutter_test example/lib example/test
dart analyze
dart run tool/check_release.dart
dart run tool/license_notices.dart --check
dart test --concurrency=1 --timeout=2m
(cd packages/marionette_agent_util && dart test --concurrency=1 && flutter test flutter_test)
(cd example && flutter test)
dart run integration_test/release_smoke.dart
(cd website && bun install --frozen-lockfile && bun run verify)
```

After dependency changes, regenerate `dart run tool/license_notices.dart`, review
notices, and rerun the check. The smoke installs into a fresh private directory,
checks version and notices, launches/connects tester, observes tap=0, taps to 1,
fills to 5 characters, captures, closes, and verifies daemon cleanup. It redacts
raw output and preserves a live runtime if cleanup fails. Set
`MARIONETTE_RELEASE_SCREENSHOT` to a private absolute file path to retain the
capture for visual inspection. A tester result does not establish native/iOS
behavior; follow [runtime verification](runtime-verification.md) and coordinate
Simulator resources before native acceptance checks.

## Publication checklist

- [ ] Release changes are reviewed and integrated into `develop`; final tree is clean.
- [ ] Above gates and required iOS/native acceptance pass on the exact candidate.
- [ ] Fresh source checkout/locked resolution/install/smoke succeed; inspect capture.
- [ ] License notices match exact dependencies, SDK, and chosen distribution assets.
- [ ] Confirm SECURITY points to the requested public Issues tracker and warns
      against posting secrets, personal information, tokens, or abuse-enabling
      details. GitHub private reporting was disabled at the 2026-10-01 read-only
      check; no private route or setting change is promised.
- [ ] CLI/util pubspec, CLI/MCP version, CHANGELOG, tag, and Release agree on 1.0.1.
- [ ] Installation examples use `v1.0.1`; verify the tag after publishing.
- [ ] Keep the site as development documentation published from `develop`; stable
      installation instructions select the release tag. The banner SHA is the
      site build revision, not a promise of the latest release.
- [ ] Obtain authorization for push/PR/merge/tag/Release; hosting or permission
      changes require their own scope.
- [ ] Confirm Pages deploy and live URLs when authorized. Run 35617308091 built,
      checked, and uploaded successfully; deploy creation returned HTTP 500 from
      GitHub. Existing workflow gates and artifact/environment names are consistent;
      logs do not prove a configuration defect. After the user merged PR #48,
      run [36854804049](https://github.com/r0227n/marionette_agent/actions/runs/36854804049)
      succeeded, including verify and deploy. No redeploy was requested by this task.

Do not remove `publish_to: none` as a release shortcut. A future pub.dev decision
needs workspace/path dependency design and a separate package-content dry run.

## Git-flow automation

The default branch is intended to be `main`. Normal development PRs still target
`develop`, including compatibility fixes. Only same-repository
`release/MAJOR.MINOR.PATCH` PRs target `main`; same-repository `fix/*` branches may
stabilize a release branch. Git flow, Quality, and Documentation verify PRs into
these branches. Git flow also reruns on base edits. Configure these as required
checks (`Git flow policy`, `Quality checks`, `Documentation checks`) before relying
on them to block merges; workflow files alone cannot do so.
Keep Pages deployment on `develop` under the existing environment policy.

1. Review version changes on `develop` before starting a release. Align all three
   pubspec versions and the protocol's public version; put substantive reviewed
   notes under the first CHANGELOG heading. Keep `publish_to: none`. The requested
   stable version must exceed `main`, and its tag must not exist. Version edits
   and release notes are deliberately reviewed development changes.
2. In Actions, select **Prepare release**, choose **main**, and enter the version
   without `v`. The default **dry_run=true** validates the fixed develop SHA and
   runs the existing macOS Quality workflow without writing branches or PRs.
   With dry run disabled, successful checks create `release/<version>` at that
   exact SHA and a Draft PR to `main`. If develop moves during verification, rerun.
   main must be an ancestor of develop; complete the previous back-sync first.
3. Review and stabilize the candidate. Bot-created PR checks may require **Approve
   workflows to run**; if checks are absent, close/reopen the PR as a maintainer.
   Do not bypass missing checks or substitute the preparation run for final PR
   checks. No PAT or extra automation secret is required. Require current
   Git flow, Quality, Documentation, and native acceptance before a human marks
   the PR ready and merges it. Prefer merge commits to retain branch ancestry.
4. A merged release PR runs Quality again on its exact merge SHA. **Release
   handoff** then saves a source archive, reviewed notes, and a manifest with the
   proposed tag and SHA as a 30-day Actions artifact. It creates no remote tag,
   GitHub Release (including draft), or pub.dev publication. Download before
   expiry; a separately authorized human publication must use that exact SHA.
5. Handoff creates an idempotent Draft PR from `sync/main-<merge-SHA>` to `develop`,
   or does nothing if develop already contains the commit. Review conflicts and
   checks, then use a **merge commit** for this PR so develop contains main's
   ancestry. Squash/rebase back-sync causes the next preparation to fail until
   ancestry is restored. Nothing auto-merges or force-pushes.

Release preparation is serialized across versions. Retries reuse unchanged
branches and open PRs, reject moved branches or closed PRs, and never overwrite
existing tags. A stabilization commit means rerunning preparation is intentionally
rejected; continue reviewing the existing release PR. If API permissions fail
after branch creation, the branch remains; resolve the permission issue with
approval and rerun to recover the PR. API errors other than an explicit 404 are
failures, not evidence that a resource is absent. Failed handoff jobs can be rerun
on the same merge event; already-integrated back-sync is a no-op.

### Initial rollout and settings requiring maintainer review

The automation must reach `main` before manual dispatch is available. First merge
this implementation PR into `develop`. For the initial rollout only, prepare a
reviewed version increment on develop, create its release branch manually and
open the Draft PR to main; run the added PR checks and human acceptance before
merging. This is a real candidate decision, not an automatic bootstrap release.
Afterward the dispatch workflow is available on main. This change does not merge,
create a release candidate, or execute publication during implementation.

At the 2026-10-02 inspection, main and develop both pointed to
`69c409c5eb317d41da4008b7f5b0adf63fd0649c`, default was develop, and v1.0.0 was already
published. Ruleset `22644545` (`block`) targets `~DEFAULT_BRANCH`, prohibits
non-fast-forward updates/deletion and requires a PR/code-owner review; it has no
required CI checks. Changing the default to main moves that ruleset's scope away
from develop. Before rollout, request approval to protect **both main and develop**,
require current CI checks and appropriate human review, and disallow bypass as
appropriate. Traditional branch-protection reads returned 403; Actions PR creation
settings could not be read with the available connection. Their state is unknown.

The write jobs need `contents: write` and `pull-requests: write`, scoped in YAML to
branch/PR creation jobs. If repository policy blocks Actions PR creation, request
approval for **Allow GitHub Actions to create and approve pull requests** (the
workflows never approve PRs), or an approved alternative; do not silently enable
it or introduce a PAT. Default-branch administration was unavailable in the task
connection; a maintainer must change it to the existing main and read it back,
without moving either branch. No settings were modified by this implementation.

GitHub references: [manual dispatch availability](https://docs.github.com/actions/managing-workflow-runs/manually-running-a-workflow)
and [GITHUB_TOKEN event behavior](https://docs.github.com/en/actions/concepts/security/github_token).
