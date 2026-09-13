# CLIのクリティカルレビュー

対象は `36aa56d` 時点の `packages/marionette_agent/` 全体。CLI解析、IPC、session、対象解決、backend、workflow/batch、画像保存・差分、テスト配置と設計文書を確認した。差分限定のレビューではない。後方互換用の再exportや旧ファイルのshimは追加しない。

## 設計・配置

以下は既存の規約違反という扱いに限らず、責務と依存方向に対する設計判断を含む。

| 優先度 | 問題 | 修正 |
| --- | --- | --- |
| P2 | 操作handlerがArgParserを定義し、parserや公開barrelへ逆依存していた。protocolもCLIの共通オプション実装へ依存していた | 構文は `cli/commands/`、組立はcatalog、解析はparser、表示文はhelpへ分離。共通値域検証はprotocolへ置き、daemonからCLI/argsへの依存を禁止するテストを追加 |
| P2 | FakeBackendが製品libから公開され、テスト同士がRequest生成やfake定義をimportしていた。state/policy/batchは画像差分、stateはdoctorを読み込んでいた | fake・Request fixtureを `test/support/` に集約。通常ファイル読込とprocess実行を独立させ、URI正規化も具体adapterから分離 |
| P2 | snapshot差分が各行を全探索して削除するため、大きな観測の比較が二乗時間になる | 構造等価な行のhash集計で重複件数を比較。順序だけの変化を無視し、数値・ネストしたmap・重複行の等価性を維持 |

製品仕様と実装契約の配置説明、古いIPC版番号、内部handlerがbarrelをimportする記述も修正した。CLIのpublic schemaVersionは1、IPC protocolVersionは6を維持する。Dart内部型・ファイルパス・FakeBackendの公開には互換性を保証しない。

## 挙動・仕様

| 優先度 | 問題と再現条件 | 修正 |
| --- | --- | --- |
| P1 | `find` が選択した要素をselectorだけへ変換していた。matcher選択後、同じkeyで属性の異なる要素へ置き換わってもtap/fill/focus/scrollintoviewが送信された | `ObservedQuery`に選択時属性を保持し、通常resolverで送信前に照合。不一致はSTALE_REF / not_sent。4操作の回帰テストで送信0回を確認 |
| P1 | `drag` が始点・終点・始点を別々に観測し、異なる画面状態の検証結果を組み合わせていた | 両対象を同一inspect結果で検証する `resolveAll` / `performTargets` を追加。失敗ならrefを維持し、成功時だけ失効して1回送信 |
| P2 | 明示CLIでsession/timeoutを上書きしても、batchの子argv解析が不正な環境変数を再検証し、実行前に失敗した | 共通オプションは親だけで解決。子は構文・重複option・paramsだけを検証。空session/不正timeoutの環境値を親CLIで上書きする回帰テストを追加 |

仕様の正本は [SPEC](SPEC.md)、詳細は [追加コマンド](ja/cli-parity.ja.md)、実装の責務は [ARCHITECTURE](ARCHITECTURE.md) と [コマンド実装契約](ja/command-contract.ja.md) に反映した。

## 検証

- 修正前の既存281テストは成功。新規のfind 4件、dragの共通観測、batch環境値の6ケースは修正前に失敗し、修正後に成功した。
- 修正後の整形・静的解析と全291テストが成功。IPC、AOT実行形式、deadline、queue、ref、policy、workflow、画像、録画を含む。
- 大量行の差分は12,000行を逆順に並べた観測で、5秒の要求期限内に変更なしと判定した。重複行、mapのkey順序、整数と小数の同値も確認した。
- 実環境シナリオは [critical_review_smoke.dart](../packages/marionette_agent/integration_test/critical_review_smoke.dart)。fixture再起動後、CLIの結果と画面を照合する。最終実行記録と確認方法は [検証記録](../packages/marionette_agent/docs/verification/critical-review.md) に記載する。

選択から送信までのアプリ側の原子性や永続的な要素identityは追加していない。同一属性の別要素への置換は現行backendで検出できない。競合条件は決定的なfakeによる回帰確認、Simulatorは実際の操作成功と画面変化の確認を担当する。
