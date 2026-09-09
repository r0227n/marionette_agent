# marionette_agent — アーキテクチャ

本書は [SPEC.md](SPEC.md) を実現する設計。現状は `packages/marionette_agent/bin/marionette_agent.dart` の引数解析の雛形であり、以下は実装予定。

## 構成

```text
AI Agent / Shell
  → Dart CLI（解析・出力・ファイル保存）
  → Unix domain socket（ローカルIPC）
  → Dart daemon（session・直列実行・snapshot/ref）
  → Marionette adapter（VmServiceConnector）
  → Dart VM Service WebSocket
  → marionette_flutter（iOS Simulator内のFlutterアプリ）
```

1ユーザー・1ランタイムディレクトリに1daemonを置く。daemonはsessionごとに独立したconnectorとキューを所有する。CLIとdaemonはDartで実装し、MCPプロセスは介在しない。

### 予定ディレクトリ

```text
packages/marionette_agent/
  bin/marionette_agent.dart
  lib/src/
    cli/        # parser、text/JSON renderer、artifact writer
    protocol/   # versioned request/response、error、DTO
    daemon/     # 起動、socket server、dispatch、期限と直列化
    session/    # lifecycle、接続所有権
    snapshot/   # 正規化、ref、対象の事前検証
    backend/    # Backend interface、Marionette adapter
    commands/   # 共通サービスを使う各操作
  test/         # 単体・IPC・契約テスト
  integration_test/ # SimulatorでのCLIシナリオ
```

protocolはDartの値とJSONだけを扱う。コマンド層はBackend interfaceに依存し、上流connectorやresponse mapを直接扱わない。rendererはbackend例外を解釈しない。

## Marionette adapter

`package:marionette_mcp/src/vm_service/vm_service_connector.dart` のVmServiceConnectorを再利用する。内部API依存はadapterに限定し、実装開始時にリリースの実体を検証してpubspecで完全固定し、lockfileも管理する。現在の `^0.6.0` は固定済みとはみなさない。

隣の `../marionette_mcp` は参考ソースであり、pubの解決済みバージョンと一致するとは限らない。接続、response形状、identifier、swipeを固定候補に対して検証してから採用する。配布時に隣接リポジトリへのpath依存を要求しない。

| ローカル操作 | 上流呼び出し |
| --- | --- |
| connect / close | connect / disconnect |
| snapshot | getInteractiveElements |
| tap | tap |
| fill | enterText |
| swipe / 初版scroll | swipe |
| screenshot | takeScreenshots |
| logs | getLogs |

adapterはURI正規化、wire変換、response検証、例外分類を担当する。HTTP→WS、HTTPS→WSSへ変換するとき認証path/queryを保持し、`/ws` を重複追加しない。機能不足はUNSUPPORTED_CAPABILITY。成功メッセージ文字列だけで成否を判定しない。

Backend interfaceはconnect、disconnect、inspect、tap、fill、swipe、captureScreenshots、readLogsを型付き引数・結果で提供する。上流mapは境界で閉じる。scrollは同じswipe primitiveを使い、helpと出力はscrollとして返す。

## IPCとdaemon起動

CLIは要求1件を送り、最終応答1件を受けて終了する。IPCは改行区切りJSON。要求はprotocolVersion、requestId、session、command、params、deadlineを持つ。応答はrequestIdとSPECの結果包絡を持つ。CLIのJSON schemaとIPC protocolのバージョンは独立させる。

ランタイムディレクトリはユーザー専用・権限0700。socketと起動情報も他ユーザーから読めない権限にする。macOSのsocketパス長に収まる短いパスを生成する。起動情報にはPID・protocolVersion・起動識別子を含め、VM Service URIは永続化しない。

OSの排他ロックで起動を直列化し、取得後に稼働daemonを再確認する。CLIの実行形態（Dartソース／コンパイル済み）に応じて同じプログラムを内部daemonモードで起動する。handshake完了を待ち、バージョン不一致は説明可能なエラーにする。

古いsocketは生存確認とロックのもとで回収し、PIDだけを根拠に別プロセスをkillしない。最後のcloseと新規connectは管理キューで直列化する。終了中へのconnectは送信前なら再接続できるが、送信後のUI操作は再送しない。

IPCのサイズ上限は初版で1フレーム64MiB。画像はbase64としてdaemonからCLIへ返し、超過は明示エラー。ファイル保存は呼出元CLIが担い、相対パスは呼出元のcwdで解決する。

## sessionと実行順序

sessionはconnecting→connected→disconnected、closeで破棄。接続失敗時はconnectorをdisposeする。名前、正規化URI、connector、接続世代、snapshot、実行キューを所有する。daemon全体でref採番とURI所有権を管理する。

同一sessionの観測・検証・操作は1つのキュー上で実行し、異なるsessionには別キューを使う。受付時と実行前に期限を確認し、期限切れの未送信要求は実行しない。

UI操作は、引数・session確認→対象解決と再観測→ref失効→バックエンドへ1回送信→結果返却の順。成功dataにはrequiresSnapshot: trueを含める。

送信後の通信断・timeoutはoutcome: unknown。connectorを破棄しdisconnectedにする。Dart Futureのtimeoutだけでは上流処理が取り消されないため、接続世代を照合し、遅延応答が新しい状態を書き換えないようにする。

## snapshotとref解決

SnapshotServiceは要素情報を正規化し、RefStoreはref→観測世代・selector・要素属性を保持する。key、identifier、対応確認済みtext、typeの順で一意な候補を選ぶ。公開snapshotと内部の事前観測は分離し、事前検証が新しいrefを発行しないようにする。

Marionetteの要素一覧は完全なツリーではなく、Semanticsの表示用textがTextMatcherに対応しない場合がある。配列添字をselectorにせず、対象を確定できなければ読み取り情報と理由を返す。上流は最初の一致を選ぶため、契約テストには重複・Semanticsラッパー・非表示要素を含める。

事前観測では原子的な対象保証にならない制約はSPECに従う。アプリ側への永続ID拡張追加は初版に持ち込まない。

## モデル間の実装境界

Astraはprotocol、session、daemon、backend、snapshot/refとswipeを実装する。別モデルはtap、fill、scroll、screenshot、logs、利用ガイドと統合を担当する。

Astraは引き継ぎ前に、型付きinterface、CommandContext、エラー変換、FakeBackend、コマンド登録方法、正常・異常応答fixtureを提供する。CommandContextにsession実行・対象解決・期限・失効を集約し、個別コマンドが再実装しない形にする。具体的なDart型はコア実装時に確定し、契約テストで固定する。

別モデルが基盤変更を必要とする場合は、todoに理由・依存を記録してAstra担当へ戻す。共通契約を黙って変更しない。担当モデル名の記録だけで完了にしない。

## 検証

- 単体: 引数の排他・有限値、JSONと終了コード、ref失効・曖昧性・session分離。
- adapter契約: 固定依存のresponse fixtureとFakeBackendでマッピング・異常系を確認。
- IPC: 別CLIプロセス間の保持、同時起動、並行session、close競合、daemon停止、送信前後のtimeout。
- Simulator: 独立した2アプリ、入力欄、PageView、Dismissible、スクロール領域、ログのfixtureでSPECの完了条件を検証。

FakeBackendの合格はSimulator検証の代わりにしない。コード変更時はパッケージ内でformat、analyze、関連testを実行し、引き継ぎ時は全体testも実行する。Simulator検証にはFlutter／bindingバージョン、Simulator機種・OS、コマンド、観測結果を記録する。
