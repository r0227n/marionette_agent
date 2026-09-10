# PR #19 レビュー検証

- 状態: 完了（2026-09-11）
- 担当: GPT-6 / Codex
- 対象: [review 5172477512](https://github.com/r0227n/marionette_agent/pull/19#pullrequestreview-5172477512)。元レビューの対象は6db5c72、検証・修正の基点は最新d93ee44。
- 作業branch: `feature/pr19-review-validation`。`git gtr new ... --from feature/device-recording --porcelain`、hook_status: ran。
- 依存する録画実装は基点に含まれる。utilの終了通知・disposeは指摘対象であり、有界終了契約を満たすため変更した。
- このbranchには既存todo.mdがなかったため、利用者の指示に従って今回の作業記録を新規作成した。

## 指摘の判定と修正

| コメント | 判定 | 根拠と対応 |
| --- | --- | --- |
| [3983682411](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682411) 混在hunk | 説明不足。Majorは強めだが改善は妥当 | 既に無関係な変更の保持は要求しており、データ破壊の実例ではない。同一ファイル内の混在変更についてpatch staging・専用worktree・staged diffとcommitの検査を明示した。 |
| [3983682417](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682417) 同時録画 | 再現手順の説明不足 | 2コマンドを同一シェルへ貼ると直列実行になる。ただし過去の同時録画が虚偽だったという根拠ではない。別ターミナルでの開始、SIGINT、終了待ちを明示した。 |
| [3983682443](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682443) stdout/stderr | 実在する異常系の問題 | UTF-8 decodeエラー後のdoneでCompleterが二重完了し得る。process終了前やtimeout後のFutureのエラーも未処理になり得る。終端Futureと即時のFuture.waitハンドラを使い、両pipeの完了も期限内で待つ。timeout後はpipeを待たない。録画プロセスの出力Futureにも即時にハンドラを付けた。 |
| [3983682451](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682451) endedのエラー | 再現した不具合 | 修正前のテストで期待failedに対しrecordingのまま。エラーを受けても共通finalizationへ合流させる。修正後は失敗状態が記録され、同じ端末を再利用できる。 |
| [3983682457](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682457) smokeのfinally | 実在する制御フローの問題 | closeの例外が元の例外を置換し、結果保存と削除を省略する。全cleanupを試み、最初の例外とstackを保持する。提案のようにcloseの失敗を常に握りつぶすと偽成功になるため、それは採用しなかった。 |
| [3983682470](https://github.com/r0227n/marionette_agent/pull/19#discussion_r3983682470) shutdown期限 | 最新実装でも再現した不具合 | d93ee44はstart応答を有界にしたが、disposeは遅延handleのcleanupを無期限に待つ。開始が戻らないケースでdisposeの外側200ms期限が切れることを確認。全体60秒＋強制停止等の追加待ち5秒を導入。staging削除は復旧仕様に反するため、未確定動画と予約先を保持する。読込をキャンセルし、遅延完了による成功扱い・保存を防ぐ。 |

## 自動検証

- util: `dart format lib test`、`dart analyze`、`dart test`。18件成功、静的解析の指摘なし。
- CLI: `dart format lib test/daemon_shutdown_test.dart integration_test/record_smoke.dart`（その他の変更testもformat済み）、`dart analyze`、`dart test`。135件成功、静的解析の指摘なし。
- 回帰テスト: 不正UTF-8→done、終了前stderrエラー、timeout後のエラー、終了後も開いたpipe、endedエラー、戻らないstart/stop、停止したファイル読込、遅延停止後の保存抑止、daemonの終了とsocket/metadata削除、cleanup失敗時の元例外・証跡保存処理・削除処理の維持。
- 一時Git repositoryで同一ファイルの2hunkを変更し、`git apply --cached --unidiff-zero`でタスクhunkだけをstage・commit。commitにはタスク変更だけが入り、無関係hunkが作業ツリーに残ることをassertして成功。
- `skill-creator/scripts/quick_validate.py .agents/skills/pr-create`: Skill is valid。
- `git diff --check`成功。SPEC・ARCHITECTURE・日本語CLIリファレンスのshutdown契約とリンクを照合した。

## iOS製品CLI検証

Flutter 3.47.2 / marionette_flutter 0.6.0、iPhone 17 Pro Simulator / iOS 26.2。

```sh
# example/で実行。認証URIは表示・記録しない。
flutter run -d 022CF629-91E1-48F0-816B-2D86B8CD1D38 --debug --no-pub --vmservice-out-file=/tmp/mra-pr19-review-uri

# packages/marionette_agent/で実行。
MARIONETTE_RECORD_PLATFORM=ios \
MARIONETTE_RECORD_DEVICE=022CF629-91E1-48F0-816B-2D86B8CD1D38 \
MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-pr19-review-uri \
MARIONETTE_RECORD_EVIDENCE=/tmp/mra-pr19-review-evidence \
dart run integration_test/record_smoke.dart
```

期待／実際: 接続なし録画開始→connect→タブ往復→tap/fill→状態照会→stop→重複stop→上書き拒否→新規録画→close確定→cleanupがすべて成功。19回の呼び出し中、上書き拒否だけが期待した終了コード1、残りは0。

`before.png` / `after.png`とsnapshotでTap count 0→1、Not edited→19 charactersを確認。`operations.mp4`の12秒フレームでも入力結果とOSのソフトウェアキーボードを確認。

- operations.mp4: 14.975秒、2,547,879bytes。
- close.mp4: 2.056667秒、481,531bytes。
- `ffprobe`で両動画のduration/sizeを確認。
- 元タイムスタンプをそのままnull muxerへ渡す復号では、operations動画に非単調DTSの警告が出た（終了コード0）。元動画は変更せず、`ffmpeg -v error -err_detect explode -i <video> -vf 'setpts=N/(30*TB)' -f null -`でフレーム復号だけを検査し、両動画とも終了コード0・stderrなし。元動画のタイムスタンプ整合性を検証済みとはしない。
- 証跡はローカルの`/tmp/mra-pr19-review-evidence/`。`results.json`に全CLI結果、PNG・動画・抽出フレーム・decode logを保持した。

## 残る制約

- 今回の実環境再検証はiOS。Android/macOSの強制終了経路は実端末で再検証していない。
- OS内で進行するファイルI/O自体の取消しと、切断されたAndroid端末の強制停止は保証できない。期限後は復旧用ファイルを削除せず、正常終了扱いにしない。
- SIGKILL後の自動復元や動画タイムスタンプ補正は今回の変更対象外。
