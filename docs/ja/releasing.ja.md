# リリース準備と配布

[English](../releasing.md)

## 現在の配布と対象

公開版は固定Gitタグと、ソースarchiveを持つGitHub Releaseから導入します。1.0.1は`v1.0.1`を指定し、commit済みlockfileを解決して手元でコンパイルします。CLI/util/exampleの`publish_to: none`を維持し、Pub global activationとpub.dev公開は対象外です。開発版はレビュー済みdevelop commitを指定でき、そのSHAを記録し、リリース版と同じ動作を前提にしません。

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
- [ ] CLI/util pubspec、CLI/MCP表示、CHANGELOG、tag、Releaseが1.0.1で一致する。
- [ ] 導入例は`v1.0.1`を指定し、公開後にタグを検証する。
- [ ] サイトは`develop`から公開する開発文書を維持し、stable版の導入手順はリリースタグを指定する。bannerのSHAはサイトのビルド基点で、最新リリースの約束ではない。
- [ ] push/PR/merge/tag/Releaseの許可を得る。hostingや権限の変更は別途対象を定める。
- [ ] 許可後にPages deployとlive URLを確認する。run 35617308091ではbuild/check/uploadが成功し、GitHubのdeploy作成がHTTP 500を返した。既存workflowのgateとartifact/environment名は整合し、ログから構成欠陥は確認できなかった。ユーザーによるPR #48マージ後、[run 36854804049](https://github.com/r0227n/marionette_agent/actions/runs/36854804049)はverify/deployとも成功した。このタスクからredeployは要求していない。

公開の近道として`publish_to: none`を外さないでください。将来pub.devを選ぶ場合、workspace/path依存の設計とpackage内容のdry-runを別途行います。

## Git-flow自動化

既定ブランチは`main`を想定します。互換性修正を含む通常の開発PRは引き続き`develop`向けです。`main`は同一リポジトリの`release/MAJOR.MINOR.PATCH`からのみ受け入れ、releaseへの安定化修正は同一リポジトリの`fix/*`から行います。Git flow、Quality、Documentationが各PRを検証し、base変更時にはGit flowも再実行します。マージを確実に止めるにはrequired check（`Git flow policy`、`Quality checks`、`Documentation checks`）設定が必要で、workflowの追加だけでは強制されません。Pagesは既存environment方針に従い`develop`から公開し続けます。

1. 開始前にdevelopで版数変更をレビューします。3つのpubspecとprotocolの公開版数を揃え、CHANGELOGの先頭にレビュー済みの具体的な変更内容を記載します。`publish_to: none`を維持し、mainより大きい安定版番号を使い、同名タグが存在しないことを確認します。版数編集とリリースノートはレビューする開発差分です。
2. Actionsの**Prepare release**で**main**を選択し、`v`なしの版数を入力します。既定の**dry_run=true**ではdevelopのSHAを固定し、既存macOS Qualityを実行するだけでbranch/PRを書き込みません。dry runを無効にすると成功後にそのSHAから`release/<version>`とmain向けDraft PRを作成します。検証中にdevelopが進んだ場合は再実行します。mainがdevelopの祖先である必要があるため、前回の逆同期を先に完了してください。
3. 候補をレビュー・安定化します。bot作成PRの検証には**Approve workflows to run**が必要な場合があります。checkがない場合はmaintainerがPRをclose/reopenしてください。未実行checkを迂回したり、準備時の検証で最終PR検証を代替したりしません。PATや追加secretは不要です。最終候補のGit flow・Quality・Documentationとnative受入確認を満たしてから、人間がReady化・mainへのmergeを判断します。履歴維持のためmerge commitを推奨します。
4. release PRのmerge後、そのmerge SHAでQualityを再実行します。**Release handoff**がソースarchive、レビュー済みノート、タグ候補とSHAのmanifestを30日保存のActions artifactとして生成します。remote tag、GitHub Release（draftを含む）、pub.devは作成・公開しません。期限前に取得し、別途許可された人間の公開ではそのSHAを指定してください。
5. handoffは`sync/main-<merge-SHA>`からdevelop向けDraft PRを冪等に作成します。developが既にcommitを含む場合は何もしません。競合とCIを確認して**merge commit**で取り込み、mainの祖先関係を維持します。逆同期をsquash/rebaseすると、祖先関係を復元するまで次の準備は失敗します。auto-mergeやforce-pushは行いません。

準備は版数をまたいで直列化します。再実行では変更されていないbranchとopen PRを再利用し、変更済みbranchやclosed PRは拒否し、既存タグを上書きしません。安定化commit後のprepare再実行は意図的に拒否するため、既存release PRのレビューを続けてください。branch作成後にAPI権限で失敗した場合はbranchが残ります。権限問題を承認付きで解決して再実行するとPR作成から回復します。明示的な404以外は「存在しない」ではなく失敗として扱います。handoffの失敗jobは同じmerge eventで再実行でき、逆同期済みなら何もしません。

### 初回導入とrepository設定

手動dispatchにはworkflowがmainへ入っている必要があります。PR #51でdevelopへ導入済みです。初回の1.0.1候補は、そのレビュー済みdevelopから手動で`release/1.0.1`を作成し、版数増加をmain向けrelease PRでレビューします。追加されたPR検証と人間の受入確認を経てmergeしてください。その後mainからdispatchでき、以降は前述のdevelop上で版数変更をレビューする通常手順に従います。

2026-10-02の初回調査時、main/developはいずれも`69c409c5eb317d41da4008b7f5b0adf63fd0649c`で、既定はdevelop、v1.0.0は公開済みでした。ruleset `22644545`（`block`）は当時`~DEFAULT_BRANCH`のみを対象にしており、CI必須checkはありませんでした。承認された導入作業でmaintainerが既定を既存mainへ変更し、対象を`refs/heads/main`と`refs/heads/develop`の両方へ明示変更しました。PR/code-owner、非fast-forward・削除禁止、迂回なしの既存条件は維持しています。設定変更によってbranchの履歴は移動していません。

maintainerは、PR作成と承認を一体で許可する**Allow GitHub Actions to create and approve pull requests**について別途承認を得て有効化しました。本workflowはPR作成だけを行い、承認reviewは投稿しません。既定のGITHUB_TOKENはcontents/packages読取のみを維持し、branch/PR作成jobだけがYAML内で`contents: write`と`pull-requests: write`を要求します。追加のPATやsecretは使いません。初回release PRのmerge前に、前述の3つのCI checkが必須化されていることを確認してください。正確なcheck名と初回成功runはPR #51から確認できます。追加の保護・権限変更には明示承認が必要です。

GitHubの参照: [手動dispatchの条件](https://docs.github.com/actions/managing-workflow-runs/manually-running-a-workflow)、[GITHUB_TOKENによるeventの扱い](https://docs.github.com/en/actions/concepts/security/github_token)。
