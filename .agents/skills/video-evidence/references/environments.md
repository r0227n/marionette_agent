# 実行環境と録画元

録画元のOSと編集ホストを分ける。iOS・Android・Webのローカル動画を、macOSまたはLinuxで同じ手順により編集する。ネットワーク・GUI・AppKitは編集時に不要。

## 依存の準備

Python 3.9以降、Pillow、fonttools、FFmpeg／ffprobe、使用文字を含むTTF／OTF／TTCを事前に用意する。macOSなどでは専用venvで [requirements.txt](../scripts/requirements.txt) を使える。

```sh
python3 -m venv <job-root>/.venv
<job-root>/.venv/bin/python -m pip install -r <skill-root>/scripts/requirements.txt
```

以後の `python3` はそのvenvのPythonへ置き換える。フォントは利用環境にあるローカルファイルを `VIDEO_EVIDENCE_FONT` に設定する。日本語には [Noto Sans CJK](https://github.com/notofonts/noto-cjk) の日本語faceを使える。フォントの自動ダウンロード・OSフォントの暗黙選択は行わない。

Codex CloudなどのLinux環境では、環境準備時にPython描画依存、日本語フォント、必要な機能を持つFFmpegを導入し、入力動画とログをその環境のファイルとして用意する。Debian 13なら [Dockerfile](../Dockerfile) のパッケージ群を準備の参考にできる。Docker daemonがない環境もPythonから直接実行できる。Cloud上でmacOSや端末の録画機能まで利用できるという意味ではない。

FFmpegの `-enc_time_base filter` と `-enc_time_base demux` を含め、[編集手順](editing.md) の機能をローカルヘルプで確認する。古いFFmpegに合わせて固定fpsを加えるとVFRの証拠が変わるため、対応ビルドを準備する。

## Dockerで編集する場合

依存取得はイメージ構築時に行う。編集時のコンテナには動画用ジョブルートだけを渡す。以下はリポジトリrootで実行する例。

```sh
docker build -t video-evidence:local .agents/skills/video-evidence
docker run --rm --network none --read-only --tmpfs /tmp \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$VIDEO_EVIDENCE_JOB,dst=/job" \
  video-evidence:local python3 /opt/video-evidence/scripts/render-caption.py \
  1140 340 job-01/.work/caption.txt job-01/.work/caption.png \
  --font /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc --font-size 48
```

`VIDEO_EVIDENCE_JOB` は存在する専用ジョブルートの絶対パス。`/job` 以下のパスはホストのジョブルートへ対応する。Dockerfileの既定フォントはNoto Sans CJKのindex 0。FFmpeg／ffprobeも同じコンテナのコマンドとして実行できる。コンテナ内のプレビューPNGはマウント先へ保存し、Agent側で閲覧する。

DockerfileはDebianの描画パッケージを利用し、venv用の版固定とは独立する。OS・ライブラリ・フォント・FFmpegの実際の版とイメージIDを結果に記録する。別環境でPNGがバイト一致する保証はせず、それぞれで文字と配置を確認する。

補助スクリプトの検証は `VIDEO_EVIDENCE_FONT` を設定して [test_render_caption.py](../scripts/test_render_caption.py) を実行する。単体確認に加え、採用する環境で実録画へ合成し、全フレームPTSと出力PNGを確認する。

## 録画元

| 録画元 | このリポジトリでの取得経路 | 編集時の確認 |
| --- | --- | --- |
| iOS Simulator | macOSで [simulator-verify](../../simulator-verify/SKILL.md)。製品CLIの `record --platform ios` のMP4 | 端末UDID、物理pixelとFlutter論理pixel、VFR |
| Android | [CLIのrecord](../../../../docs/ja/cli-reference.ja.md) の `--platform android`。明示したadb serialのMP4 | Emulator／実機の識別、回転、黒帯とアプリ座標の対応 |
| Web | 製品CLIの `--platform web` はmacOSの可視Chrome＋指定ディスプレイのMOV。ブラウザー操作は既存の操作手段を使う | タブ・display、ブラウザー枠や他ウインドウ、CSS pixelと録画pixel |
| Webのheadless録画 | 既存のブラウザーテストが生成したWebM／MP4を入力として受け取る | viewport、device pixel ratio、録画の縮小・余白、ブラウザーの操作／状態ログ |

製品CLIのホスト制限・端末指定は [SPECの端末画面録画](../../../../docs/SPEC.md#端末画面録画) を参照する。このskillはCLIのLinux録画やheadless録画機能を追加しない。WebMの入力でも、映像が1本・無音・SDR・固定寸法など [編集手順](editing.md#入力と環境) の条件を満たし、デコードとPTS照合が通れば同じH.264 MP4へ出力できる。

Android／Webの新規撮影でも、専用端末・ブラウザーprofile・runtime・出力を用意し、操作後の状態を確かめ、所有する録画とプロセスを終了する。既存録画を使う場合は撮影時の検証commitと出典を残し、今回撮影したとは書かない。
