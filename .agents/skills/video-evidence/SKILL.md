---
name: video-evidence
description: Edit marionette_agent iOS, Android, and Web verification recordings with FFmpeg to show the operation, where to look, and the observed result. Use when preparing annotated 動作確認動画 or swipe evidence for this repository's PRs.
---

# Video Evidence

`marionette_agent` の実録画から、操作対象と確認箇所が分かる動画を作る。このリポジトリのiOS・Android・Web検証用。編集はmacOS／LinuxのFFmpegとPythonで行い、AppKit・GUI・`drawtext`を必要としない。Codex CloudなどのLinux環境には録画済みファイルを渡せる。依存の準備やDocker利用時は [実行環境と録画元](references/environments.md) を読む。

## 1. 証拠と確認観点を揃える

入力は録画、実行したCLIの引数・応答、操作前後のsnapshot、期待する画面変化。録画がない、または操作の前後が欠ける場合は [録画元別の経路](references/environments.md#録画元) で撮影する。iOS Simulator検証は [simulator-verify](../simulator-verify/SKILL.md) で対象checkoutの `example/` を起動し、製品CLIから操作・録画する。端末の割当・runtime分離・終了処理は同skillに従う。Webの操作ログは既存のブラウザー操作手段から受け取り、Marionette CLIによる操作と区別する。

各場面について次を文章にする。

- **操作**: 実際に実行したCLIと対象。swipeの方向は指の移動方向。
- **見る場所**: 枠で示すUIと、確認する文字・表示。
- **観測結果**: 操作後のsnapshotと画面で確認できた変化。期待値だけなら「期待」と明示する。

swipeの成功応答はページ切替を保証しない。たとえば `page_view` のleft後に `page_result` が `Current page: 2` になり、Page 2が見えることを別途照合する。Dismissibleでは項目の消失と `Item dismissed` を確認する。入力・認証URIは字幕へ載せない。

## 2. 原動画を調べて計画を保存する

[編集手順](references/editing.md) を読み、依存と入力のメタデータ・フレームPTSを確認する。最初は操作前後のPNGを抽出し、動きのある部分を細かく調べる。粗い間隔の静止画だけでジェスチャーの有無を判断しない。

録画・作業・出力を置く私有ジョブルートを決め、その中の相対パスで `edit-plan.json` を保存する。リポジトリ外のジョブはPR本文では `<external-path>` に置換する。原動画のハッシュを記録し、新しい出力ディレクトリを使う。

計画には元動画、検証commit、要求区間 `[in_ms, out_ms)`、操作と結果、注釈の表示区間、枠の矩形、出力先を含める。元動画時刻と、最初の採用フレームを0とした出力時刻を分ける。指定が「計画だけ」ならここで `planned` として返す。

矩形は実寸PNGで確認した**動画の物理pixel**。CLIの `get box` はFlutter論理pixel、WebのDOM座標はCSS pixelなので直接転用しない。device pixel ratio、ブラウザーの余白、録画範囲を実画像と照合する。録画の回転や寸法が変わる場合は対応関係を確定してから進める。

## 3. 確認箇所を編集で示す

操作前→操作中→操作後が連続して残る範囲を採用する。結果をよく見せるために失敗・待ち時間を削ったり、速度変更・フレーム補間・UIの再描画を加えたりしない。切り出した区間と追加した注釈を明記する。

枠は操作対象と結果表示へ絞り、文字は**録画画面内**の余白か検証対象外の領域へ置く。1場面の説明を短くし、操作に合わせて切り替える。対象・変化・エラーを隠す場合は位置や文量を調整し、画面内に収まらない場合だけ画面外の説明欄を検討する。方向表示には「指の方向」と記し、実際のタッチ軌跡として見せない。日本語の文言は実行された操作と観測結果を区別する。

この経路は1本の無音SDR動画から1つの連続区間を出す。複数区間は別ジョブに分ける。音声・HDR・回転・非正方画素・途中の寸法変更など未検証の素材は理由を返し、無断で情報を落とさない。マスクが必要な場合は手順の固定矩形マスクを使い、動く秘密情報は再撮影などで解決する。

## 4. 編集結果を検証する

完成判定には、新規生成、原本ハッシュ不変、H.264／yuv420p・寸法・無音、全編デコード、実際のフレーム時刻の照合が必要。FFmpegの終了0やファイルの存在だけでは完了にしない。

**編集済み動画から**先頭・末尾・動作中・結果・注釈切替前後のPNGを取り出し、文字の欠落・枠のズレ・UIの隠れを確認する。可能なら全編を再生する。画像閲覧できない場合は視覚確認を未実施として `needs_review` にする。アプリの合否はCLI検証記録に残し、動画の生成成功と分ける。

`result.json` に要求区間、採用した元フレームの先頭／末尾PTS、出力の実測時間・寸法・フレーム数、加工内容、各検証結果、視覚確認した出力フレーム、未確認事項を保存する。測定できない値は `null` とし、要求値を実測値として転記しない。完了は `success`、未確認は `needs_review`、処理失敗は `failed`。

## 5. PRへ引き渡す

編集済み動画・確認済みPNGの絶対パス、各場面の元時刻→出力時刻、「どこを見ればよいか」、CLI検証記録を [pr-create](../pr-create/SKILL.md) へ渡す。PR公開は依頼された範囲で行う。PR本文ではFFmpeg／Pythonのコマンドやログを転載せず、編集方法と検証結果を文章で説明する。

原動画・探索PNG・認証URI・raw runnerログは私有領域に保持し、自動添付しない。必要な添付は編集済み候補を実際に確認して選ぶ。人間の動作確認は未実施として残す。
