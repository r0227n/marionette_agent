# リリース準備と配布

[English](../releasing.md)

## 現在の配布と対象

公開版は固定Gitタグと、ソースarchiveを持つGitHub Releaseから導入します。1.0.0は`v1.0.0`を指定し、commit済みlockfileを解決して手元でコンパイルします。CLI/util/exampleの`publish_to: none`を維持し、Pub global activationとpub.dev公開は対象外です。開発版はレビュー済みdevelop commitを指定でき、そのSHAを記録し、リリース版と同じ動作を前提にしません。

installerの配布物は実行ファイルと、対応する隣接`.marionette-agent-*`ディレクトリです。SkillsとLICENSE/NOTICE/THIRD_PARTY_NOTICESを含め、移設・再配布でも保持します。upgradeは旧bundleを残すので、実行ファイルが参照しなくなったものだけ削除してください。アプリ側utilも同じcheckoutを使います。複数platformのビルド済み配布物は約束しません。

## ライセンス確認

本プロジェクトのコードと文書は[leancodepl/marionette_mcpのLICENSE](https://github.com/leancodepl/marionette_mcp/blob/main/LICENSE)を参考にApache-2.0としました。2026-10-01確認のblobは`261eeb9e9f8b2b4b0d119366dda99c6fd7d35c64`です。NOTICEには本プロジェクトの寄稿者を記載し、上流の権利を取り込みません。THIRD_PARTY_NOTICES.txtに依存の原文を保持します。generatorはCLI/util/exampleのproduction依存をたどり、アプリ側Flutter/engineとDart runtimeも含めます。ライセンス不足で失敗し、`--check`は更新漏れを検出します。宣言した依存全体を広めに含め、全てがAOTに組み込まれるとは主張しません。

MarionetteはApache-2.0、image/archiveはMIT、Dart/Flutterの各packageはBSD等です。元の表示を保持してください。Flutter 3.47.2でcommit済みlockfileを解決して生成します。依存・SDK変更時は同梱素材やpackage内の入れ子の第三者表示も再確認します。生成結果は法的適合性の自動判定ではありません。

skills-lock.jsonの外部開発skillは[mattpocock/skills](https://github.com/mattpocock/skills)のMITで、`third_party/mattpocock-skills-LICENSE`に元の表示を保持しました。上流LICENSE blobは`f1dd2c09108dde1a5f56097cee8461b3ea834499`です。CLIにはインストールしません。同梱Skillsは本プロジェクトの素材です。exampleのFlutter scaffold/iconsを含むアプリ配布時はFlutter/engineとcupertino_iconsの表示も保持してください。websiteのビルドツールはCLI binaryに含めません。生成サイトや新素材の再配布は別途対象を確認します。

## ローカルの検証

macOS、Flutter 3.47.2、Dart 3.13.2を基準に、ルートから以下を実行します。子directory指定は括弧内です。processを多用するtestの競合を避けて直列実行します。CLI test runnerの`--timeout=2m`はhosted macOSでの子processのcold JIT起動を含む待機枠です。製品のdeadlineとtestで明示したtimeoutは引き続き適用されます。tester smokeはnative appをビルドせず、Simulatorも起動しません。

この検証の前にffmpegとffprobeを導入してください。どちらかがない場合、実MP4エンコードの2件はskipされます。リリース検証では両方を実行する必要があります。CIはmacOS runnerに両toolを用意します。Releaseの配布物には含めません。

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

依存変更後は`dart run tool/license_notices.dart`で再生成し、表示をレビューして検証をやり直します。smokeは新規private directoryへのinstall、版と表示の照合、tester起動・接続、tap=0の観測、tapで1、fillで5 charactersへの変化、撮影、close、daemon終了を検査します。raw出力は秘匿し、終了できないruntimeは保持します。画像確認用には`MARIONETTE_RELEASE_SCREENSHOT`にprivateな絶対保存pathを指定してください。testerでiOS/nativeの動作確認を代替せず、[実環境検証](runtime-verification.ja.md)とSimulator資源調整を行います。

## 公開チェックリスト

- [ ] リリース差分をレビューして`develop`へ統合し、最終treeがcleanである。
- [ ] 候補そのもので上記検証と必要なiOS/native受入確認が成功する。
- [ ] 新規ソースcheckout、固定依存の解決、install、smokeが成功し、撮影画像を確認した。
- [ ] 正確な依存・SDK・配布素材にライセンス表示が対応する。
- [ ] SECURITYが指定された公開Issuesを窓口とし、秘密情報・個人情報・トークン・悪用可能な詳細の投稿を避けるよう案内している。GitHubの非公開報告は2026-10-01の読み取りで無効で、非公開窓口や設定変更を約束しない。
- [ ] CLI/util pubspec、CLI/MCP表示、CHANGELOG、tag、Releaseが1.0.0で一致する。
- [ ] 導入例は`v1.0.0`を指定し、公開後にタグを検証する。
- [ ] サイトは`develop`から公開する開発文書を維持し、stable版の導入手順はリリースタグを指定する。bannerのSHAはサイトのビルド基点で、最新リリースの約束ではない。
- [ ] push/PR/merge/tag/Releaseの許可を得る。hostingや権限の変更は別途対象を定める。
- [ ] 許可後にPages deployとlive URLを確認する。run 35617308091ではbuild/check/uploadが成功し、GitHubのdeploy作成がHTTP 500を返した。既存workflowのgateとartifact/environment名は整合し、ログから構成欠陥は確認できなかった。ユーザーによるPR #48マージ後、[run 36854804049](https://github.com/r0227n/marionette_agent/actions/runs/36854804049)はverify/deployとも成功した。このタスクからredeployは要求していない。

公開の近道として`publish_to: none`を外さないでください。将来pub.devを選ぶ場合、workspace/path依存の設計とpackage内容のdry-runを別途行います。
