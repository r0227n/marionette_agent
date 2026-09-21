# Documentation website

Astro + Starlight documentation with English as the default public language and complete Japanese counterparts. User guides live here; repository supplements cover additional contracts without repeating those guides. Read the [documentation policy](../docs/documentation.md) ([日本語](../docs/ja/documentation.ja.md)) before adding or moving content.

## Local development

Use Bun 1.4.2, pinned by `.tool-versions` and `package.json`’s `packageManager`. With mise, run `mise install` in `website/` to select the pinned runtime. Run all commands below from this directory.

```sh
bun install --frozen-lockfile
bun run dev
```

Open `http://localhost:4321/marionette_agent/` for the English entry or `http://localhost:4321/marionette_agent/ja/` for Japanese. Both languages keep explicit `/en/` and `/ja/` URLs. Search is generated during production builds.

```sh
bun run --bun playwright install chromium
bun run verify
bun run preview
```

`verify` checks formatting, Astro types, matching bilingual page paths and examples, paired repository supplements and their incoming links, the production build, generated links/anchors/assets/SEO, and browser behavior. Browser tests start a production preview. Stop any existing server on port 4321 before a CI-mode test run. Failures save traces and screenshots in `test-results/`; the HTML report is in `playwright-report/`.

Astro, Prettier, and Playwright explicitly run on Bun through `bun run --bun` in the scripts. Custom checks run on Bun too. Use `bun run test` for Playwright, not `bun test`.

Use Bun to change dependencies and commit `bun.lock` alongside them. CI installs with `--frozen-lockfile`. A Bun update must change both version declarations and pass the complete verification. GitHub Actions manage their own execution runtimes separately from the site’s Bun runtime.

Documentation-only changes require link/specification/site checks. They do not require Simulator or Dart tests when CLI code and behavior are unchanged. CLI changes still follow the repository’s normal verification rules.

## Authoring

- Add corresponding paths under `src/content/docs/en/` and `ja/`. Frontmatter supplies the page h1, title, and description.
- Keep executable examples identical and translate their explanations outside code blocks. Automated parity checks do not replace reviewing both languages for equal meaning and current behavior.
- Write around the reader’s task and verify commands, defaults, and restrictions against implementation and SPEC.
- Use `/marionette_agent/<locale>/.../` for site links. Sidebar slugs omit the locale. Link to the matching language when referring to repository supplements.
- `site.config.mjs` owns origin, base, locale order, and default locale. `astro.config.mjs` owns sidebar labels and entries. Update content/test URLs and verify everything when changing the base.
- Put downloads in `public/examples/`. The workflow download must match the guide’s example.
- Keep English supplements directly in `docs/`, Japanese in `docs/ja/`, and update `scripts/check-repository-docs.mjs` when adding a pair. These files are not imported into the site.

The headless guide owns managed startup, platform selection, rendering recordings, and cleanup. `guides/manual-headless.md` owns manual runner setup. The old `docs/*headless*` entry files now contain only migration links.

## GitHub Pages

The deployment URL is `https://r0227n.github.io/marionette_agent/`. Adding workflow files alone does not enable Pages in repository settings.

On 2026-09-21, this repository’s Pages source was configured as GitHub Actions and the `github-pages` environment was configured to allow `develop`. The first publication awaits merging this workflow into `develop`. For another repository, configure these settings explicitly:

1. Select **GitHub Actions** under Settings → Pages → Build and deployment.
2. Allow Actions, the GitHub official actions in this workflow, and Bun’s `oven-sh/setup-bun`.
3. If `github-pages` restricts branches, allow `develop`. Fulfill any configured environment approval at deployment time.
4. Merge the PR into `develop` and verify both jobs in the Documentation workflow.
5. To redeploy manually, select **develop** under Actions → Documentation → Run workflow. Other branches only run verification.

PRs verify without deploying. Relevant changes on `develop`, or manual runs on `develop`, publish the verified `dist/` as a single Pages artifact. Only the deploy job has `pages: write` and `id-token: write`; no PAT is required. Generated HTML is not committed.

PR verification builds GitHub’s merge commit. Deployment rebuilds from the actual `develop` commit. Each page banner identifies the package version from the CLI pubspec and the built SHA. During local uncommitted work, the SHA refers to the checkout’s HEAD.

This site describes a development version. Before switching to stable documentation, change deployment to a release tag, stop automatic publication from `develop`, and align the version banner and installation instructions.

## Human acceptance

Open the root and confirm it selects English. Follow both home pages into the quick start and switch languages while staying on the same page. Search for “recording”, “録画”, and “STALE_REF” and open results in the selected language. Open the headless guide, follow manual setup, and verify its language switch. At mobile width, inspect the menu, long commands, and tables. Check that the 404 page offers both language entries.

To verify CLI behavior, separately follow the example quick start and inspect the tap count and input changes in Simulator. Website browser tests do not verify Flutter operations.
