---
title: 実行環境を選んで起動する
description: tester・iOS・Android・macOS・Webのheadless起動と、所有資源の終了方法。
---

`launch`は、選んだ環境でアプリをビルド・起動し、接続と最初の観測まで行います。ホストはmacOSです。実行環境を明示し、失敗時に別環境へ自動で切り替えることはありません。

## 起動前の準備

Flutter SDK、projectの依存関係、選択した環境のSDKや端末を用意します。`launch`は`--no-pub`でビルドするため、先にアプリのディレクトリで`flutter pub get`を実行してください。初回のビルド時間も含めてtimeoutを指定します。

| platform  | 用途と追加条件                                                          |
| --------- | ----------------------------------------------------------------------- |
| `tester`  | Flutter共通UIの確認。検証済みSDKはFlutter 3.47.2                        |
| `ios`     | 専用device setで起動。Xcodeとインストール済みdevice type・runtimeが必要 |
| `android` | 既存AVDを非表示で起動。Android SDKと空いている偶数portが必要            |
| `macos`   | ネイティブアプリ。アプリ側の非表示window対応が必要                      |
| `web`     | headless Chrome。Google Chromeが必要                                    |

## testerで小さく始める

依存取得済みのリポジトリルートから実行します。

```sh
marionette-agent --session fast --timeout 600000 launch ./example --platform tester
marionette-agent --session fast snapshot
marionette-agent --session fast fill --key text_input 'headless check'
marionette-agent --session fast snapshot
marionette-agent --session fast --timeout 60000 close
```

testerはdebug用のFlutterエンジンです。このSDKでのviewportは論理800×600、DPR 3です。iOS・Androidのネイティブ機能や実機性能を再現するものではありません。

## iOS・Androidを選ぶ

iOSでは`--device-type`と`--runtime`、Androidでは`--avd`と`--port`を指定します。以下の識別子・名前は例なので、ローカルに用意したものへ置き換えてください。

```sh
marionette-agent --session ios --timeout 600000 launch ./example --platform ios \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
marionette-agent --session ios --timeout 60000 close

marionette-agent --session android --timeout 600000 launch ./example --platform android \
  --avd Pixel_9_Pro --port 5586
marionette-agent --session android --timeout 60000 close
```

Androidのportは5554〜5682の未使用の偶数です。AVDは読み取り専用で起動し、保存済みの状態へ変更を書き戻しません。同じprojectのビルド出力を共有しないよう、管理対象の起動はprojectごとに1つです。

macOSやWebも`--platform`で選びます。macOSは任意のアプリを自動で非表示対応にするわけではありません。exampleにある非表示windowとdebug描画維持の実装を参考にしてください。ログイン済みGUI環境を使い、WindowServerがないホストでの動作を前提にしないでください。

## 録画と後片付け

接続後の操作は通常のCLIと共通です。[Flutter描画の録画](/marionette_agent/ja/guides/capture/)には`--platform flutter`を使います。

`close`は録画を確定してから、そのsessionが起動したアプリ・端末を終了します。共有Simulatorやadb server全体を停止しません。起動失敗やtimeoutでは所有資源の回収を試みますが、ホスト停止・強制終了後の自動復元はありません。アプリが終了したらrefは失効し、自動再起動も行いません。
