# Documentation and detailed references

[日本語](ja/README.md)

Start with the [English documentation site](https://r0227n.github.io/marionette_agent/en/) for installation, everyday commands, and guides. Before deployment or offline, read the [site source](../website/src/content/docs/en/getting-started/overview.md) or use the [local preview](../website/README.md).

These supplements cover details beyond the site. English files live directly in `docs/`; their Japanese counterparts live in `docs/ja/`.

| Supplement | Read when you need | 日本語 |
| --- | --- | --- |
| [Product specification](SPEC.md) | CLI contracts, supported scope, errors, lifecycle, MCP, and recording | [製品仕様](ja/SPEC.ja.md) |
| [Architecture](ARCHITECTURE.md) | Module responsibilities, dependency direction, and implementation boundaries | [アーキテクチャ](ja/ARCHITECTURE.ja.md) |
| [CLI runtime details](cli-reference.md) | Output budgets, MCP, Skills, image persistence, and recording behavior | [CLI実行の詳細](ja/cli-reference.ja.md) |
| [Advanced operation details](cli-parity.md) | Provider behavior, find, keyboard input, differences, batches, and policies | [追加操作の制約](ja/cli-parity.ja.md) |
| [Workflow file reference](workflow-file-spec.md) | Schema, binding, limits, and failure progress | [workflowファイル仕様](ja/workflow-file-spec.ja.md) |
| [Headless guides](headless.md) | Follow the migration links to managed and manual startup on the site | [headlessガイド](ja/headless.ja.md) |
| [Command implementation contract](command-contract.md) | Developing handlers and backend adapters | [コマンド実装契約](ja/command-contract.ja.md) |
| [Documentation policy](documentation.md) | Choosing a location and updating both languages | [文書の配置・翻訳方針](ja/documentation.ja.md) |

Existing Japanese filenames remain valid entry points. Duplicated installation instructions, basic command lists, quick starts, and managed-launch guides have been removed from those supplements.

## Internal documents

The product specification and architecture above are maintained in both languages as current development contracts. Research, ADRs, and [agent workflows](agents/) serve separate purposes and may remain in Japanese outside this paired set. Historical research records are not current user guides.
