# 動作確認動画skillの実録画検証

[video-evidence](../../.agents/skills/video-evidence/SKILL.md) の初回受入記録。CLI本体の変更は含まない。

## 検証対象と結果

2026-09-13にCLIのcommit `36aa56df8e2457f0de4fabf446de7a89be7edfa2` のクリーンな一時コピーから `example/` を起動し、同じコピーのDart entrypointで20回のCLI呼出しを実行した。別タスクの未コミット変更は含めていない。

macOS 26.5.2、Flutter 3.47.2、Dart 3.13.2、marionette_flutter 0.6.0、iPhone Air／iOS 26.2。端末UDIDは `C66CFC02-289C-4106-8F63-93DF694BB2C4`。専用runtimeとsessionを使い、record停止・close・daemon終了・runner終了・アプリ終了を確認してSimulatorをShutdownへ戻した。

| 確認 | 期待・実際 |
| --- | --- |
| PageView left、距離240論理px | `Current page: 1` → `Current page: 2`。実画面もPage 2に切り替わった |
| PageView right、距離240論理px | `Current page: 2` → `Current page: 1`。実画面もPage 1に戻った |
| Dismissible left、距離300論理px | 項目が消え、画面とgetで `Item dismissed` を確認 |
| 文字配置 | 原画内の検証対象外のFill領域に短い日本語説明を重ね、操作ごとに切り替えた。PageView・結果・削除対象は隠れない |
| メディア | 元・編集後とも1260×2736、無音、H.264／yuv420p。元23.453333秒、編集後23.453秒（要求終端）。136フレームすべてのPTSが一致。原本ハッシュ不変 |
| 視覚確認 | 編集済み動画の10フレームで初期・各結果・削除中・注釈切替の直前直後・最終状態を確認。全編デコードは終了0、stderr空 |

最終版はPython・Pillow・明示したNoto Sans CJKフォントでPNGを生成し、LinuxのFFmpeg 7.1.5で合成した。macOSのFFmpeg 9.0.1には再確認してもdrawtextがなかったが、Python経路で日本語を表示できた。AppKit・GUI・外部AI APIは不要。Dockerではネットワークなし・root filesystem読み取り専用・非rootユーザーで編集した。

元動画の要求範囲は `[0, 23453)` ms。先頭元PTSは0、最終元PTSは23451.667 ms。注釈の実切替時刻は0、11215、17918.333 msで、元時刻と出力時刻は同じ。原画の寸法・動作速度を維持し、追加したものは注釈と枠だけ。エンコード時は各packetの表示時間を次のPTSまで、最後を要求した区間末尾までに設定した。

別途、非キーフレームを含む4.55〜12.6秒の切り出しも検証。最初の採用PTSは4.565秒、全101フレームの相対PTSが一致した。固定マスクの0〜0.5秒について29フレームの対象内部が黒、後続72フレームで解除されることを画素でも確認した。

Python補助スクリプトの7テストはmacOSとLinuxの両方で成功した。日本語・記号を含む文字列とパス、結合文字、折り返し、既存出力・symlinkの保護、文字あふれ・空文字・不足glyph・不正引数を確認した。macOSはPython 3.9.6／Pillow 11.3.0／fonttools 4.59.1、LinuxはPython 3.13系／Pillow 11.1.0／fonttools 4.57.0。skill frontmatter検証とローカルリンク確認を通過。CLI本体は変更しておらず、録画した同一コードで実施済みのformat（106ファイル変更なし）、静的解析（指摘なし）、全281テスト成功を再利用した。

## Android・Webと編集ホストの検証

| 入力と出典 | 編集ホスト | 実測結果 |
| --- | --- | --- |
| 今回撮影したiOSのスワイプMP4 | Debian 13 Docker、FFmpeg 7.1.5 | 136フレームの全PTS一致、1260×2736、23.453秒、出力10フレームを視覚確認 |
| 過去の全CLI確認で撮影したAndroid EmulatorのMP4 | 同じDocker | 元20〜26秒を選択。最初の採用PTS 21.002078秒、30フレーム、最大PTS差1µs（time_base 1/90000以内）、720×1280、4.997922秒 |
| 今回専用headless Chromeで撮影したWebM（VP8） | 同じDocker | 96フレームの全PTS一致、1280×720、3.84秒 |
| 上記WebMをH.264 MOVにした形式検証用素材 | macOS、FFmpeg 9.0.1 | 96フレームの全PTS一致、1280×720、3.84秒 |

すべて無音のH.264／yuv420p MP4へ合成し、全編デコード成功。注釈と枠は元画面内で確認対象を隠さない。Androidは撮影時のCLIログにあるleft・距離250と `Current page: 2` を画面と照合した。原本SHA-256は `5a887d2a854120d20df75b61c50de007c6714cf9f7d0eee4368627765a41be15`。撮影時のcommitは付属ログから確定できないため、今回のCLI受入検証には数えず、既存Android録画の編集検証として扱う。

WebはChrome 151.0.7922.34、viewport／録画1280×720の専用ローカルHTMLで横スクロールを実行し、DOMと画面の `Current page: 1` → `Current page: 2` を確認した。ブラウザーとcontextは終了済み。これはWeb録画の編集検証であり、製品CLIによるWeb操作・headless録画を追加／検証したという意味ではない。Codex Cloudサービスそのものの実行は未実施。Linuxへ依存と録画を用意して直接実行できる手順と、Dockerでの実動作を確認した。

FFmpeg 7.1で従来の末尾duration制限を使うと、Androidの結果表示時間が短くなり、WebM由来のMP4では最終フレームがデコードから落ちた。次のPTSと要求終端からdurationを定める修正後、フレーム数・全PTS・要求終端をすべて照合して上記結果を得た。

## CLIの実行記録

以下は録画・操作・観測の実結果。コマンドpathをリポジトリ相対へ変換し、外部ジョブrootを `<external-path>`、接続URIを `<redacted-uri>` に置換した。実行時は外部ジョブ内の私有runtimeを全呼出しで共有した。stdinによる追加入力はない。JSONは読みやすく整形し、snapshotは対象要素だけの抜粋（その他の要素・属性を省略）。各コマンドは終了0。stderrは接続時の診断ログのみで、その他は空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json connect '<redacted-uri>'
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "name": "video-evidence",
    "state": "connected",
    "uri": "<redacted-uri>",
    "snapshotValid": false,
    "connectionGeneration": 1
  },
  "error": null
}
```

stderr（認証URIは秘匿済み）:

```text
[INFO] VmServiceConnector: Connecting to VM service at <redacted-uri>
[INFO] VmServiceConnector: Service registered: reloadSources -> s1.reloadSources
[INFO] VmServiceConnector: Service registered: hotRestart -> s1.hotRestart
[INFO] VmServiceConnector: Service registered: flutterVersion -> s1.flutterVersion
[INFO] VmServiceConnector: Service registered: compileExpression -> s1.compileExpression
[INFO] VmServiceConnector: Service registered: flutterMemoryInfo -> s1.flutterMemoryInfo
[INFO] VmServiceConnector: Connected to isolate: isolates/7601249938194431
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json scroll --key operation_scroll_area up --distance 200
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "requiresSnapshot": true,
    "command": "scroll"
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json get text --key page_result
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "text": "Current page: 1"
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json record start '<external-path>/media/raw.mp4' --platform ios --device C66CFC02-289C-4106-8F63-93DF694BB2C4
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "recordingState": "recording",
    "platform": "ios",
    "device": "C66CFC02-289C-4106-8F63-93DF694BB2C4",
    "path": "<external-path>/media/raw.mp4",
    "startedAt": "2026-09-13T09:07:36.555343Z",
    "elapsedMs": 0,
    "bytes": null
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json swipe --key page_view left --distance 240
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "requiresSnapshot": true
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json snapshot
```

入力は上記引数。終了0。stdout抜粋（対象要素のkey/text/visibleのみ）:

```json
{
  "elements": [
    {
      "key": "page_result",
      "text": "Current page: 2",
      "visible": true
    },
    {
      "key": "dismissible_item",
      "visible": true
    }
  ]
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json get text --key page_result
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "text": "Current page: 2"
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json swipe --key page_view right --distance 240
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "requiresSnapshot": true
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json snapshot
```

入力は上記引数。終了0。stdout抜粋（対象要素のkey/text/visibleのみ）:

```json
{
  "elements": [
    {
      "key": "page_result",
      "text": "Current page: 1",
      "visible": true
    },
    {
      "key": "dismissible_item",
      "visible": true
    }
  ]
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json get text --key page_result
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "text": "Current page: 1"
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json swipe --key dismissible_item left --distance 300
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "requiresSnapshot": true
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json snapshot
```

入力は上記引数。終了0。stdout抜粋（対象要素のkey/text/visibleのみ）:

```json
{
  "elements": [
    {
      "key": "page_result",
      "text": "Current page: 1",
      "visible": true
    },
    {
      "key": "dismiss_result",
      "text": "Item dismissed",
      "visible": true
    }
  ]
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json get text --key dismiss_result
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "text": "Item dismissed"
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json record stop
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "recordingState": "stopped",
    "platform": "ios",
    "device": "C66CFC02-289C-4106-8F63-93DF694BB2C4",
    "path": "<external-path>/media/raw.mp4",
    "startedAt": "2026-09-13T09:07:36.555343Z",
    "elapsedMs": 25052,
    "bytes": 630778
  },
  "error": null
}
```

stderr: 空。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --session video-evidence --json close
```

入力は上記引数。終了0。stdout:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "video-evidence",
  "data": {
    "closed": true,
    "recording": {
      "recordingState": "stopped",
      "platform": "ios",
      "device": "C66CFC02-289C-4106-8F63-93DF694BB2C4",
      "path": "<external-path>/media/raw.mp4",
      "startedAt": "2026-09-13T09:07:36.555343Z",
      "elapsedMs": 25052,
      "bytes": 630778
    }
  },
  "error": null
}
```

stderr: 空。

## 人間による再現

1. 対象branchの `example/` をiPhone Airなどの未使用Simulatorでdebug起動する。アプリを再起動してPage 1・削除前へ戻す。VM Service URIを私有ファイルへ新しく取得する。
2. [simulator-verify](../../.agents/skills/simulator-verify/SKILL.md) に従い、短い専用runtimeとsessionを用意して接続する。上記のscroll操作でPageViewとDismissibleを表示する。
3. 製品CLIのrecordを開始し、上記のleft→right→dismissを実行する。各操作後にsnapshotとget、画面で結果を照合し、recordを停止する。
4. [編集手順](../../.agents/skills/video-evidence/references/editing.md) に沿って録画を調べ、実寸の空き領域に短い注釈を置く。録画時刻は実行ごとに変わるため、この記録の時刻を無条件に再利用しない。
5. 編集後の動画を開き、文字が画面内にあり、対象を隠さず、黄色・水色・紫の枠から確認箇所が分かることを確認する。時間・フレームの照合、closeとrunner停止まで実施する。

- [ ] 人間が変更と動画を確認した

## エビデンス

編集動画は外部ジョブの `job-04/edited.mp4`、編集計画は `job-04/edit-plan.json`、実測結果は `job-04/result.json`。PRには編集動画と確認済みの必要なフレームを添付する。原動画・探索PNG・raw runnerログは私有領域に保持する。

動画の前半は黄色のPageViewと水色のCurrent pageで1→2→1、中盤以降は紫枠で削除ジェスチャーとItem dismissedを見る。上部の3行説明は操作に合わせて切り替わる。人間の動作確認は未実施。
