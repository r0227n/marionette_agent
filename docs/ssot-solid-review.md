# SSOT / SOLID クリティカルレビュー

2026-09-20。基点は `origin/develop` の `ec7834e`。CLI・backend adapter・session・daemon・snapshot・workflow・recording・配布処理、`marionette_agent_util`、Flutter provider、exampleの実装と関連テストを読んだ。修正は `packages/marionette_agent/` と仕様書に限定した。

既存の共通Execution、対象解決、backend adapterと機能別interfaceは有効な境界だった。一方、同じ規則を複数箇所で所有した結果、エラー応答と後始末の挙動に差が出ていた。以下の4件は修正済み。原則への適合を点数化したものではなく、再現可能な不具合と、その原因になった責務・依存関係を対象とする。

## 修正した指摘

### P2: 単一closeが切断失敗を成功として返す

単一closeは `Session.discard()` の完了を待たず、全体closeは切断完了を待っていた。backend.disconnectが例外を返しても単一closeは成功し、完了しない場合も期限を待たなかった。また、所有アプリの終了通知が先にdiscardすると、後続closeが同じ切断の失敗を観測できなかった。

[SessionManager](../packages/marionette_agent/lib/src/session/session_manager.dart) に `_disconnectSession` を置き、単一・全体closeで所有権破棄、ref失効、完了待ち、期限・例外の分類を共有した。[Session](../packages/marionette_agent/lib/src/session/session.dart) は最後の切断Futureを保持し、同じ接続への重複disconnectを防ぎながら完了結果を返す。到達不能だった別のclose分岐も削除した。

確定した失敗はBACKEND_ERROR / failed、期限超過はTIMEOUT / unknownになる。失敗、完了しない切断、所有アプリ終了との競合をテストで確認した。実Simulatorでは単一close・再接続・全体closeとdaemon終了を確認した。切断失敗の注入はfake backendで行った。

### P2: policyが実行層へ循環依存し、不正findを検証前に解釈する

policyはSessionの公開状態を書き換え、Sessionもpolicyをimportしていた。batch/workflowの定義を読むだけでもhandlerからCommandContext・registryへ依存が広がっていた。さらにfind.actionを検証せずStringへcast・再帰解釈しており、数値や `find` / `batch` / `workflow` の指定で、INVALID_ARGUMENT以外の結果や不要な保留承認を生んだ。

[SessionActionPolicy](../packages/marionette_agent/lib/src/session/action_policy.dart) にpolicyと承認状態を非公開で所有させ、Requestと接続世代だけで判定する形にした。batch・find・interaction・waitの入力定義を副作用のない `*_request.dart` へ分離し、findは共通validatorを通した後に内包操作を解釈する。

不正入力は観測・UI送信・承認作成前にINVALID_ARGUMENTとなり、既存snapshotを保持する。依存グラフのテストで、policyからSession・CommandContext・registry・daemon・CLIへの推移的依存を禁止した。実Simulatorではfind、batch、workflowの各承認、再利用拒否、click/tapの同一policyを確認した。

### P2: waitの定義が分散し、明示nullを既定値へ戻す

CLI・handler・workflow schemaにstateやpoll範囲が分散していた。ref待機は架空のselectorを組み立てて検証し、IPCの明示nullを省略と同じ扱いにしていた。

[WaitRequest](../packages/marionette_agent/lib/src/commands/wait_request.dart) を時間待機・対象待機の型に分け、target、state、poll間隔の検証を1箇所へ集約した。CLIとhandlerが同じparserを使い、workflow schemaもstateとpoll範囲を同じ定義から生成する。明示nullや不正型は観測前に拒否する。workflow v1のselector限定という既存契約は維持した。

null拒否とref保持をテストし、実Simulatorでref・selector・時間待機、poll間隔50/1000の受理と49/1001の拒否を確認した。SPECと日本語CLI referenceに残っていた「waitはrefを受理しない」という古い説明も修正した。

### P2: 結果のsession判定が重複し、close --allのエラーで食い違う

CLIの通常解析、構文エラー回復、Invocation、IPC client/managerでsession非依存コマンドを別々に列挙していた。`close --all --timeout 0` と未知optionの構文エラーは、全体操作なのに選択sessionを返していた。

[usesSession](../packages/marionette_agent/lib/src/protocol/command_scope.dart) を共通定義にし、CLI・Request・daemonの応答経路で使用した。IPCではworkflow実行だけを送るため、Request側でrunとして判定する。構文エラー回復でも、optionの値として現れた `--all` をflagと誤認しない。

上記2種類のエラーをCLI parserと実CLIで確認した。両方ともsession:null、終了2となり、runtimeを生成しなかった。

## 原則ごとの判断

| 観点 | 判断と対応 |
| --- | --- |
| SSOT | 入力規則、結果scope、切断完了の所有を統一。JSON schemaとCLI表現自体を同一化するのではなく、意味上同じstate・範囲を共有した。 |
| SRP | policyの状態管理をSessionから分離し、入力検証から実行層への依存を除去した。SessionManagerは接続所有・queue・lifecycleの調停を維持する。 |
| OCP | 既存のcommand registryとbackend capabilityによる拡張点を維持。今回の4件に汎用plugin機構や新しい基底classは不要と判断した。 |
| LSP | deadline、送信結果の分類、stale ref、未対応capabilityの既存契約を全体テストで確認。実backendとfakeがあらゆる条件で置換可能であるとの証明ではない。 |
| ISP | InteractionBackend、ClipboardBackend、ScreenshotConnection等の任意機能interfaceを維持。未対応機能を基本Backendへ追加しなかった。 |
| DIP | 上流内部importのbackend adapter集約を維持。policyは具象Session・handlerに依存せず、入力定義とRequestへ依存する。 |

`get` / `is` / `session` の親コマンド余剰引数についても検証したが、既存parserが拒否していたため修正対象から外した。ファイルの大きさやswitchの存在だけを根拠とする分割は行っていない。

## 検証と範囲

- 基点のCLI全314テスト成功。追加回帰テストでは修正前に5件の失敗を確認し、所有アプリ終了競合も修正前の失敗を確認した。
- 最終コードのformat・analyze成功、CLI全322テスト成功。IPCとコンパイル済み実行ファイルのテストを含む。
- iOS Simulator上のexampleに製品CLIで接続し、32呼び出しの期待結果を確認。画面のカウンタ0→3を2枚のscreenshotで確認した。
- [検証記録と人間向け再現手順](../packages/marionette_agent/docs/verification/ssot-solid-review.md) を参照。

`marionette_agent_util`、Flutter provider、exampleは読み取りレビューとiOS検証の対象であり、今回は変更していない。Android/Web実環境での再検証は実施していない。今回のレビューは全不具合の不在を保証しない。人間による動作確認は未実施としてDraft PRで引き渡す。
