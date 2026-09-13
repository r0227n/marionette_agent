# Issue #14 検証記録

状態: ソース調査、必須Simulator実payload/画面確認、関連チェック、資源の終了確認済み。新CLI機能は実装していない。人間確認は未実施。

対象Issue: https://github.com/r0227n/marionette_agent/issues/14

branch: `feature/issue-14-semantics-contract`。worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-14-semantics-contract`。検証した製品コードと通常exampleは `50ccf97f47ecf03a51ea3c5646c9164325570c0b` と同一。このIssueの最終diffは文書と観測JSONのみ。調査fixture/probeは[再現用文書](issue-14-research-fixture.md)のDart blockとbyte単位で一致し、一時Dartファイルは検証後に削除した。

## 環境・固定ソース

| 項目 | 実測/照合結果 |
| --- | --- |
| 実施日 | 2026-09-12 |
| SDK | Flutter 3.47.2、Dart 3.13.2、macos_arm64 |
| binding | marionette_flutter 0.6.0、example/pubspec.lock archive sha256 `9bf6aa531157edeb3d94f7c4972367240a1d704bbe9f4ac558ef1a125c4d1a6d` |
| connector | marionette_mcp 0.6.0、packages/marionette_agent/pubspec.lock archive sha256 `24a2b3277c659367e3d6c306d35d35600fc78c5d28512f06bc843cb2e65e21b3` |
| package root | `/Users/r0227n/.pub-cache/hosted/pub.dev/marionette_flutter-0.6.0`、同directoryの`marionette_mcp-0.6.0` |
| Flutter source | `/Users/r0227n/.local/share/mise/installs/flutter/3.47.2` |
| device | iPad Air 13-inch (M3)、iOS 26.2、UDID `5A240A9B-AC1A-47EC-9C30-8D1F208DC460` |
| runtime/session | `/tmp/mra-i14.FbmyPA/runtime` / `p1-issue-14`、bundle `com.example.example` |
| fixture source SHA256 | `b0dd3a81c09c45ce38ef0e5806ac0d63ea396e438ead0b4f91da5aad2b8110d6` |

[設計のF1〜T3](../../../../docs/semantics-selector-state-design.md)を解決済みpackage_config・lockfile・ソースと照合した。既存`test/fixtures/binding_0_6_0.json`は合成fixtureであり、今回の実payloadとは区別する。実測のFilledButtonにtextがないこと、diagnosticsが追加されることは抽出/走査ソースと整合した。

## 実行結果

全CLI呼出しはこのworktreeの`packages/marionette_agent/bin/marionette_agent.dart`を使用し、同じ専用runtimeと`--session p1-issue-14 --json`を指定した。認証URIは私有ファイルから読み、ログや記録へ転記していない。

| 手順 | 期待と実際 |
| --- | --- |
| Shutdown確認、boot/bootstatus、通常exampleを`flutter run --debug --no-pub` | 指定iPadのみ起動。build成功 |
| connect → snapshot → screenshot | 成功。空のTest input、Not edited、Tap count 0を画像で確認 |
| `fill --key text_input 'issue14'` → snapshot/raw/screenshot | 成功。画面はissue14と7 characters。入力elementにはraw/CLIともtext/valueなし |
| `fill --key text_input ''` → snapshot/raw/screenshot | 成功。空欄と0 characters。入力elementにはraw/CLIともtext/valueなし |
| close、runner終了、研究fixtureで起動 | baseline daemon/runner停止後に同じexample projectを別targetで起動。最終fixture build成功 |
| 研究fixtureのconnect/snapshot/raw/screenshot | 成功。明示Semantics、重複label、checked/mixed、controller入力、disabled入力、mixed Checkboxを画面とrawで照合 |
| `wait --text 'Shared label'` | exit 4、AMBIGUOUS_TARGET、not_sent |
| `wait --text 'Volume: 70%'` | exit 4、UNRESOLVABLE_TARGET、not_sent |
| `wait --identifier semantics_full` | exit 6、UNSUPPORTED_CAPABILITY、not_sent |
| エラー後screenshot | 前画像とSHA256も同一。開いて状態不変を確認 |
| close、runner q、app/daemon確認、shutdown | 全て終了。owned appのlaunchctl entryなし、daemon.json/socketなし、iPad Shutdown。URIファイル削除済み |

途中の研究fixture準備では`SemanticsRole.slider`がenumに存在せずanalyzeで検出、`spinButton`はSDKのdebug validatorで未対応だった。最終fixtureはSDKソースで対応を確認した`tabPanel`を使用し、analyze/build/実画面を再確認した。失敗時の画面をエビデンスには使用していない。

[実payload JSON](issue-14-payloads.json)にはbaseline/filled/cleared/researchの対象element、対応CLI要素、3つの期待エラー、画像hashを保存した。対象element内のfieldは省略していない。原本は`/tmp/mra-i14.FbmyPA/evidence/*-raw.json`。全て合成入力のみ。

重要な実測は、Semanticsのlabel/value/hint/tooltip/role/checked/mixedが診断stringとして現れる一方、明示Semantics enabled:falseは欠落し、mixed Checkboxのchecked/value/mixedも欠落したこと。TextFieldのenabled true/falseとFilledButtonのenabled trueもstringであり、nullable TextFieldでは欠落した。placeholderはdecoration stringに含まれるだけ。これらから共通typed capabilityを主張しない。

## 関連チェック

| チェック | 結果 |
| --- | --- |
| 変更文書の相対リンク、SPEC/ARCHITECTURE/CLI説明とIssue条件の照合 | 成功。現行と将来案を区別 |
| `git diff --check` | 成功 |
| 一時fixtureの`dart format` | 1 file、変更0 |
| 一時fixtureの`dart analyze lib/issue14_research.dart` | 最終版No issues found |
| raw probeのanalyze | No issues found |
| exampleの`flutter test --no-pub --concurrency=1` | 5 tests passed。通常exampleの回帰確認であり、新しいselectorのテストではない |
| 文書のDart blockと実行fixture/probeの比較 | byte一致 |
| 保存JSONの構文、raw/CLI属性差、エラーcode/outcome、画像hash照合 | 成功 |

SDKのDart実体は`/Users/r0227n/.local/share/mise/installs/flutter/3.47.2/bin/cache/dart-sdk/bin/dart`。fixtureの関連チェックは私有`example-tests.log`等に保存した。初期phaseの不要な全体Dart suiteはsandbox/timeout失敗後にcoordinatorが停止したため、全体passは主張しない。baselineのformat driftも変更していない。利用者の指示どおり、文書のみの最終diffにはリンク/仕様/タスク整合性を適用し、全体suiteを再実行していない。

## エビデンス

全5画像を`view_image`で開いて確認した。PRへ添付する絶対pathは以下。raw runnerログとURIは添付しない。

| path | 示す状態 |
| --- | --- |
| `/tmp/mra-i14.FbmyPA/evidence/baseline.png` | 通常example、初期の空欄/Not edited |
| `/tmp/mra-i14.FbmyPA/evidence/filled.png` | issue14入力と7 characters |
| `/tmp/mra-i14.FbmyPA/evidence/cleared.png` | 入力クリアと0 characters |
| `/tmp/mra-i14.FbmyPA/evidence/research.png` | 明示属性の研究fixture、controller付き入力、disabled入力、mixed Checkbox |
| `/tmp/mra-i14.FbmyPA/evidence/research-after-errors.png` | 3つのread-onlyエラー後の同一画面 |

## 人間の再現手順

1. 対象branchをcheckoutし、予約/所有が確認できた上記iPadがShutdownであることを確認する。通常exampleを再起動して初期状態へ戻す。他のworkerの端末を使わない。
2. `umask 077`で`mktemp -d /tmp/mra-i14.XXXXXX`を実行し、その返却pathを`MRA_I14_DIR`へ保持する。`MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I14_DIR/runtime"`をexportし、evidence directoryをmode 700で作る。以下の全terminalで同じpath/sessionを使う。
3. 上記UDIDを明示して`xcrun simctl boot`、`bootstatus ... -b`。example内で`flutter run -d 5A240A9B-AC1A-47EC-9C30-8D1F208DC460 --debug --no-pub --vmservice-out-file="$MRA_I14_DIR/vm-uri"`を起動し、runnerログは私有directoryへredirectする。
4. シェルトレースを無効にした別terminalでURIを私有fileから読み、同worktreeのDart CLIでconnectする。snapshot/screenshot、上表のfillとclearを順に実行し、空欄→7 characters→0 charactersを画面で確認する。[probe](issue-14-research-fixture.md)で各段階のrawを保存し、input elementにtext/valueがないことを比較する。
5. closeしてdaemon終了を確認しrunnerをqで停止する。[fixture文書](issue-14-research-fixture.md)の最初のDart blockを一時的な`example/lib/issue14_research.dart`として展開し、format/analyzeを行う。同じexampleで`flutter run ... --target=lib/issue14_research.dart --vmservice-out-file="$MRA_I14_DIR/research-uri"`を起動し、新URIでconnectする。
6. snapshot/raw/screenshotを取得し、属性名とJSON型を[保存payload](issue-14-payloads.json)と照合する。上表の3つのwaitエラーと画面不変を確認する。string diagnosticsをtyped stateとして解釈しない。
7. close、runner q、owned app service/daemon残存なしを確認して指定iPadをshutdownする。Shutdown確認後に資源を返却し、一時fixtureと私有URIを削除する。rawログは公開しない。

- [ ] 人間が能力表の固定版ソースと実payload、表示/照合の分離を確認した
- [ ] 人間が通常exampleと研究fixtureの再現手順を実施した
- [ ] 人間がUnknown/Unsupported/NotApplicable/mixed、重複labelとstale制約の設計をレビューした

## 受入条件対応

| Issue条件 | 設計・根拠 |
| --- | --- |
| 属性ごとの取得/照合、version/ソース、不足primitive | 設計の能力表、F1〜T3、実測表とpayload JSON |
| 共通selectorとread-only案、textから値を捏造しない | 型付きDTO・共通selector/read-only節、入力before/afterの実測 |
| 重複label、nullable state、由来不明text、未対応fixture | 必要fixture表、明示/欠落stateのraw、現行waitの3エラー |
| 実装へ進める範囲と上流待ち | 設計の依存表。scroll-to primitiveの存在とCLI統合の未対応、完全Semantics tree不足を区別 |
| 関連文書、現行と将来の区別 | SPEC、ARCHITECTURE、CLI referenceから設計へ参照 |

上流のtyped API、対象ID/階層・atomic primitive、新CLI実装は後続依存。今回の設計調査の未実施項目ではない。PRはdevelop宛Draftとし、URL/添付URL/最終headはworker結果ファイルへ記録する。
