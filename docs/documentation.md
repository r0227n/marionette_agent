# Documentation policy

[日本語](ja/documentation.ja.md) · [Documentation index](README.md)

English is the primary public language of this OSS project. Japanese readers must be able to understand and use the same features. The site entry opens `/en/`; Japanese lives at `/ja/`. Language switching must preserve the current page.

## Where content belongs

| Content | English | Japanese |
| --- | --- | --- |
| Project overview and shortest installation path | Root `README.md` | Link to the Japanese site |
| Installation, guides, and basic reference | `website/src/content/docs/en/` | Same relative path in `website/src/content/docs/ja/` |
| Detailed contracts and development procedures supplementing the site | `docs/<name>.md` | `docs/ja/<name>.ja.md` |
| Product specification and architecture | `docs/SPEC.md`, `docs/ARCHITECTURE.md` | `docs/ja/SPEC.ja.md`, `docs/ja/ARCHITECTURE.ja.md` |
| Supplement index | `docs/README.md` | `docs/ja/README.md` |
| Site development, CI, and Pages setup | `website/README.md` | Referenced from this policy |

Do not create `docs/en/`. Keep site content in Starlight and link to the relevant guide from supplements. Supplements describe additional value ranges, edge cases, manual setup, and implementation contracts. When content moves to the site, remove its duplicate text from both supplement languages and update referring links.

The paired set covers the public site and the documents listed in the index, including [SPEC](SPEC.md) and [ARCHITECTURE](ARCHITECTURE.md). Maintain their contracts and implementation boundaries in both languages without duplicating user guides. Both versions have matching English section anchors; preserve the legacy Japanese anchors for existing links. Research, ADRs, and agent workflows serve separate purposes outside this paired set. Do not treat historical research as current user guidance.

## Updating content

1. Read the CLI implementation and SPEC; identify the changed fact and the site page or supplement that owns its explanation.
2. You may develop and write the content in Japanese first. Create the English counterpart and submit both in the same PR. Keep features and caveats equivalent.
3. Compare the meaning of titles, descriptions, constraints, and links. Keep code, JSON fields, and command names untranslated, with identical executable examples.
4. When adding or removing supplements, update both indexes and the mapping in `website/scripts/check-repository-docs.mjs`. Repair repository links when referenced headings change.
5. Run the full Bun verification and inspect both languages using the [website instructions](../website/README.md). Review translation meaning separately from mechanical parity checks.

CLI input or output changes require updates to the relevant site pages and supplements in both languages. Shared-contract changes also update SPEC and ARCHITECTURE. For documentation-only changes, record link, specification, and website verification; do not claim that these checks verify CLI behavior.

## Publishing

The Bun version, dependency lockfile, and site configuration live in `website/`. PRs run verification; changes on `develop` pass the same pipeline before publishing to GitHub Pages. Supplements in `docs/` are read on GitHub and are not automatically imported into the website. See [website/README.md](../website/README.md) for initial deployment status and setup.
