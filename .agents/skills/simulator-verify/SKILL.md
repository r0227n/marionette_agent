---
name: simulator-verify
description: Verify marionette_agent CLI changes against the example app on iOS Simulator and capture relevant screenshots or video. Use for runtime acceptance checks and PR evidence, including isolated parallel worktrees.
---

# Simulator Verify

変更したCLIでexampleを操作し、応答と実際の画面・状態を照合して、PRに使える証跡を取得する。自動テストの代替ではなく実環境の受入確認として実施する。

## 準備と分離

- cwd・branch・検証対象commitと未コミット変更を確認する。`AGENTS.md`、[example](../../../example/README.md)、[CLIリファレンス](../../../docs/ja/cli-reference.ja.md)、対象Issueの受入条件を読む。Issueのない変更でも同じ手順を使う。
- `flutter devices` または `xcrun simctl list devices available` で端末を確認する。統括Agentがいる場合は割当UDIDを使い、単独なら未使用の端末を選ぶ。端末の起動・install・操作・record・終了を1つの排他的な検証区間とする。共有端末しかないときは区間全体を直列化する。
- 統括Agentは同じホストで共有する利用記録にUDID・Issue/タスク・worker識別子・利用状態を保存する。workerの開始要求に対し、前の利用者の終了確認後に利用を割り当て、workerが開始を受領したことを記録する。終了報告とrecord/session/runnerの停止確認が揃ってから解放する。別バッチも含め同じ利用記録で調整し、稼働中か不明な利用者を経過時間だけで失効させない。独立runtimeのlockや録画予約はdaemon内だけの保護であり、端末の排他制御の代用にならない。
- 別worktreeのdaemonを使うと変更前コードを検証してしまう。session名に加え、全CLI呼出しで同じ専用 `MARIONETTE_AGENT_RUNTIME_DIR` を指定する。コード修正後の再検証では所有sessionをcloseしてdaemon終了を確認し、新しいruntimeで変更後CLIを起動する。
- 実行ごとに短い一意な私有ディレクトリを作る。runtimeの絶対pathは80 UTF-8 bytes以内、所有者は実行ユーザー、modeは0700という実装制約を満たす。URIとraw runnerログは添付用ディレクトリから分ける。例はリポジトリルートで、同じシェルまたは明示的に引き継いだ環境で使う。

```bash
umask 077
MRA_VERIFY_DIR=$(mktemp -d /tmp/mra-check.XXXXXX)
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_VERIFY_DIR/runtime"
MRA_VERIFY_SESSION=verify
MRA_VERIFY_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
mkdir -m 700 "$MRA_VERIFY_DIR/evidence"
```

## 起動・操作・取得

1. 割当worktreeの `example/` で依存を用意し、そのコードをdebugで起動する。UDIDは実在する割当値を指定する。`--vmservice-out-file` でURIを私有ファイルへ出力し、起動成功を確認する。runnerのログには認証URIが含まれるため、rawログを公開・転記しない。
2. 同じworktreeのDart entrypointからCLIを実行する。グローバルにインストール済みのCLIで代用しない。認証URIはファイルから変数へ読み、シェルトレースを無効にした状態でconnectへ渡す。表示・検証記録ではURIを取得する手順だけ残す。
3. 操作前のsnapshotと状態を取得し、受入条件に対応する操作を実行する。成功応答だけで判定せず、操作後のsnapshotと画像で期待する変化を確かめる。エラー系ではexit code・error codeと、意図しない状態変化がないことを確認する。送信結果がunknownの操作は観測し直し、無条件に再送しない。
4. 静止状態はCLIの `screenshot <absolute-path>`、遷移・ジェスチャ・録画機能は `record start <absolute-path> --platform ios --device <UDID>` と `record stop` で取得する。record自体が検証対象で正常保存できない場合は、利用可能なSimulatorの撮影手段も検討し、未達の受入条件を記録する。
5. 各画像を開き、動画は再生または時系列フレームで内容を確認する。ファイルの存在・サイズだけで合格にしない。snapshot/logs/timeout等、画像だけではCLI結果を説明できない変更には、秘匿済みのtext/JSON結果も検証記録に添える。無関係な画面をエビデンスとして選ばない。
6. 自分のrecord停止・session close・daemon終了を確認する。runnerは `q` 等で終了してアプリも停止させる。example READMEのdetachだけでは端末の解放条件を満たさない。すでにdetachした場合は割当UDIDと自分のbundle IDを指定してアプリを終了し、所有するrunner/アプリが残っていないことを確認する。次の利用者は自分のworktreeからビルド・起動し、fixtureの初期状態を確認する。この終了結果を統括Agentへ報告してから検証区間を解放する。他workerのsession・daemon・端末には触れない。URIファイルは不要になったら削除し、選択した画像・動画はPR添付確認まで保持する。

## 中断したworkerからの復旧

統括Agentがworkerの停止を確認した場合は、利用記録の専用runtime・session・runner・bundle IDと実プロセスを照合し、所有権を確認した資源だけを回収する。自分のCLIでrecordを確定しsessionをcloseしてdaemon終了を確認し、runnerと割当UDID上のアプリも終了して残存がないことを確認する。正常系と同じ終了条件が満たされたら、統括Agentの回収記録をworkerの終了報告の代わりとして保存し、端末を解放する。記録には確認した資源と終了結果、保存できたエビデンス、未完了シナリオを残す。所有権や終了状態を確認できない間はその端末を再割当せず、理由を報告して他の作業を進める。

## 完了と返却

受入条件ごとのコマンド/手順、期待結果、実際の結果、検証対象commitまたは差分、Flutter/Marionetteの版、Simulator機種・OS・UDID、画像/動画の絶対pathと示す挙動を返す。人間が初期状態へ戻し、対象branchでアプリを再起動・URIを再取得して再現できる手順も含める。

起動不能、観測不一致、必須シナリオ未実施なら理由を付けて未完了とし、実装担当へ返す。エビデンス不足はまず自分で追加取得する。[pr-create](../pr-create/SKILL.md) の添付・免除判定へ、実際に確認した候補と検証記録を渡す。
