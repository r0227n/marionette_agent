# 同梱skillsコマンドの検証

検証日: 2026-09-13。対象: `feature/bundled-skills` の本PR。エージェントによる検証は完了、人間による確認は未実施。

## 実装と参照元

agent-browserの[導入用Skill](https://github.com/vercel-labs/agent-browser/blob/main/skills/agent-browser/SKILL.md)と[skills実装](https://github.com/vercel-labs/agent-browser/blob/main/cli/src/skills.rs)を参考に、導入用stubと実行時ガイドの分離、list/get/path、複数名、--all、--full、--json、hiddenを実装した。共通の未知オプション・重複・余剰引数の検証はmarionette-agentの契約に従う。

ガイドは`packages/marionette_agent/skills/marionette-agent/`、`packages/marionette_agent/skill-data/core/`、`packages/marionette_agent/skill-data/simulator-verify/`。同梱simulator-verifyはリポジトリの既存Skillをもとに、利用者のdebugアプリでも読める独立した手順へ整理した。既存の外部管理Skillやlockは変更していない。

## Agentによる確認

- 整形・静的解析は問題なし。全体テスト291件が成功（並列数2）。最初の実行では配布テストの一時パス表記差を修正し、同時コンパイルとCLI起動が集中した実行のtimeoutは並列数を抑えた全体再実行で解消した。
- 単体・実プロセスで全コマンド形式、順序、frontmatter、非表示、UTF-8、空一覧、未知名、補助ファイルの非再帰読取、環境override、実行ファイルのsymlink、package URI、読取期限を確認した。
- AOTのinstall、既存ファイル拒否、upgrade、配置失敗時の旧版保持と新bundle回収、スペース付き配置先、配置全体の移動、対応bundle欠損時のエラーを実プロセスで確認した。
- Skillのmetadata・参照リンク、テンプレートのshell構文を確認した。テンプレートを引数記録用CLIでも実行し、通常終了・snapshot失敗の両方で所有sessionのcloseとURI非表示を確認した。標準Skill validatorでcoreとsimulator-verifyを検証した。stubはagent-browser互換の`hidden`を標準validatorが許可しないため、YAMLとしての型とCLIでの非表示・明示取得を別途検証した。
- macOS、Flutter 3.47.2 / Dart 3.13.2、marionette_flutter 0.6.0、iPhone Air / iOS 26.2、UDID `C66CFC02-289C-4106-8F63-93DF694BB2C4`。
- 同一checkoutのexampleを新規起動し、製品Dart entrypointから23回実行。接続前のskillsはruntimeを作成しなかった。接続後にskills get成功とpath失敗を挟んでも直前のrefを利用でき、tapを1回実行した後のsnapshotと画像が `Tap count: 0` → `Tap count: 1` を示した。
- 選択した2画像を開き、画面内のカウンタがそれぞれ0と1であることを確認した。close成功後にdaemon socketの消失、runnerの正常終了、所有アプリのlaunchサービス不在、SimulatorのShutdownを確認した。録画は使用していない。

### CLI結果の抜粋

以下は実際の実行結果。共通でsessionは`skills-verify`、JSONモードを使った。パスはcheckout基準の相対表記または`<verification-directory>`へ変換し、URIは`<VM_URI>`へ秘匿化した。stdin入力はない。全文ガイドと繰り返しのsnapshot行は省略し、抜粋箇所を明示する。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify skills list
```

終了0、stderr空。stdout:

```text
  core              Control a running Flutter app with marionette-agent using connect,...
  simulator-verify  Verify Flutter app behavior on iOS Simulator through marionette-agent...
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json skills path core
```

終了0、stderr空。stdout（パス変換済み）:

```json
{"success":true,"data":{"name":"core","path":"packages/marionette_agent/skill-data/core"}}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json skills get absent
```

終了1、stderr空。stdout:

```json
{"success":false,"error":"Skill not found: absent"}
```

同じ呼出しのtextモードも終了1でstdoutは空、stderrに `Skill not found: absent` を出力した。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json snapshot
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json skills get simulator-verify --full
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json skills path missing
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json tap @e3
dart packages/marionette_agent/bin/marionette_agent.dart --session skills-verify --json snapshot
```

事前にprivate URIでconnect済み。snapshotの実返却ref `@e3` を使用。終了コードは順に0、0、1、0、0。stderrはすべて空。ガイドはcontentとreferenceを返し、未知名は `Skill not found: missing` を返した（ガイド全文は省略）。tapのstdout:

```json
{"schemaVersion":1,"ok":true,"session":"skills-verify","data":{"requiresSnapshot":true},"error":null}
```

前後のsnapshotでkey `tap_result` のtextは `Tap count: 0` と `Tap count: 1`（他の要素は省略）。screenshotで取得したbefore.pngとafter.pngをPRへ添付した。

## 人間の再現手順

1. PRのcheckoutでDart/Flutter依存を準備する。`example/README.md`に従って未使用のiOS Simulator上にexampleをdebug起動し、privateなVM Service URIファイルを新規取得する。同梱simulator-verifyの準備手順に従い、端末利用記録・短い専用runtime・session・証跡出力先を分離する。
2. 次のCLIで全コマンドとガイドを読み、runtimeが作成されないこと、hidden stubが一覧から除外されること、getで全文と補助ファイルを取得できることを確認する。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart skills
dart packages/marionette_agent/bin/marionette_agent.dart skills get core simulator-verify
dart packages/marionette_agent/bin/marionette_agent.dart skills get --all --full --json
dart packages/marionette_agent/bin/marionette_agent.dart skills get marionette-agent
dart packages/marionette_agent/bin/marionette_agent.dart skills path
dart packages/marionette_agent/bin/marionette_agent.dart skills path core
dart packages/marionette_agent/bin/marionette_agent.dart skills --help
```

3. 取得したURIを`VM_URI`へ読み、次を実行する。CLI間で同じ専用runtimeを引き継ぐ。画面のカウンタ初期値0を確認し、tap後に1となることをsnapshotと新規screenshotで照合する。refは毎回実際のsnapshotから選ぶ。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session verify connect "$VM_URI"
dart packages/marionette_agent/bin/marionette_agent.dart --session verify snapshot
dart packages/marionette_agent/bin/marionette_agent.dart skills get simulator-verify --full
dart packages/marionette_agent/bin/marionette_agent.dart --session verify tap <tap_buttonのref>
dart packages/marionette_agent/bin/marionette_agent.dart --session verify snapshot
dart packages/marionette_agent/bin/marionette_agent.dart --session verify screenshot <verification-directory>/after.png
dart packages/marionette_agent/bin/marionette_agent.dart --session verify close
```

4. 自分のrunnerを終了してアプリとdaemonの停止を確認し、Simulatorを解放する。URIファイルを削除する。再試行はアプリを再起動して初期化する。

- [ ] 人間がガイド・CLI結果・実画面を確認した
