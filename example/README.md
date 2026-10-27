# Marionette Agent Example

`marionette_flutter: 0.6.0`を固定したdebug専用の検証fixture。Flutter 3.47.2を使用する。起動時にMarionetteBindingとPrintLogCollectorを設定し、操作結果を画面・snapshot・logsで観測できる。入力内容はログへ記録せず文字数だけを画面に表示する。

| key | 検証対象 |
| --- | --- |
| tap_button / tap_result | tapとカウンタ |
| text_input / fill_result | fillで置換・空文字クリア、文字数表示 |
| page_view / page_result | PageView、指のleftで次ページ、rightで前ページ |
| dismissible_item / dismiss_result | leftで削除しItem dismissed表示 |
| operation_scroll_area / scroll_result | スクロールとBottom reached表示 |
| log_button | 手動ログ追加 |

入力欄の外側をtapするとキーボードを閉じられる。初期状態に戻すにはアプリを再起動する。

Snapshot filter検証用に、keyを持たない2つの`SnapshotLabel`（Semantics派生型）を表示する。
`Filter label A` / `Filter label B`は表示textであり、操作用text matcherの確認済み型ではない。
同型の重複をfilter外に残し、`--text 'Filter label A'`へ絞っても安全でないrefが発行されないことを確認する。
同じ文言の子Textもあるため、表示textの複数一致も検証できる。identifierの公開可否は実payloadで確認する。

## 2つの独立したアプリを起動

`flutter devices`で2つのiOS SimulatorのUDIDを確認する。別Simulatorなら同じbundle IDでもプロセス・VM Service・画面状態が独立する。各runnerは別ターミナルで実行する。

依存はリポジトリルートで `flutter pub get` を一度実行する。次のrunnerは `example/` 内から起動する。

```sh
flutter run -d <SIMULATOR_A_UDID> --debug --no-pub --vmservice-out-file=/tmp/mra-a-uri
flutter run -d <SIMULATOR_B_UDID> --debug --no-pub --vmservice-out-file=/tmp/mra-b-uri
```

URIは認証情報を含むためログ・検証記録へ転記しない。各アプリを別名sessionで接続する。以下はリポジトリルートからの例。

```sh
# シェルのトレース（set -x）は使わない。
CLI=bin/marionette_agent.dart
dart "$CLI" --session alpha connect "$(cat /tmp/mra-a-uri)"
dart "$CLI" --session beta connect "$(cat /tmp/mra-b-uri)"
dart "$CLI" --session alpha snapshot
dart "$CLI" --session beta snapshot
dart "$CLI" --session alpha tap --key tap_button
dart "$CLI" --session alpha snapshot
dart "$CLI" --session beta snapshot
```

alphaのTap countだけが1、betaは0のままであることを確認する。refは別sessionへ流用できない。alphaのcloseや通信断の後もbetaが操作でき、alphaの再connect後は新snapshotが必要になる。

```sh
dart "$CLI" --session alpha close
dart "$CLI" --session beta close
```

最後に各Flutter runnerを`q`で終了し、URIの一時ファイルを削除する。動作検証はCLIの成功応答に加え、次のsnapshotと画面の変化を確認する。swipe/scrollの方向は指の動きであり、ページ切替・到達を保証しない。

自動widget確認は `flutter test`、CLIによる実環境確認は[全コマンドの動作確認手順](../docs/ja/runtime-verification.ja.md)を参照。結果と画像・動画はPR本文と添付に残す。

## UI Automatorスクリーンショット

Androidの撮影は[別のUI Automator agent](../packages/marionette_agent_android/capture_agent/README.md)を起動し、`screenshot --device <pairing-file>`で実行します。Flutter撮影、mapped provider、注釈・cropは廃止しました。iOSの表示確認はSimulatorの撮影手段またはネイティブ録画を使います。

## Workflow検証

全コマンドをiOS/Androidで確認する手順は [全コマンドの動作確認](../docs/ja/runtime-verification.ja.md) を参照してください。全7 actionを含む `all-actions.yaml` と、接続・観測・録画・終了まで実行する `all_commands_smoke.dart` を提供します。

Controls/Aboutのタブ（controls_tab/about_tab）とAbout画面のabout_contentをworkflow用に提供する。samples/workflows/reach-controls.yamlはタブ移動、wait、PageView swipe、snapshotを実行する。JSON版も同じ到達状態を検証する。

アプリを新規起動した状態で、リポジトリルートから次を実行する。URIは認証情報を含むので、ファイルのアクセス権を制限する。

```sh
MARIONETTE_TEST_VM_URI_FILE=/tmp/private-vm-uri \
MARIONETTE_TEST_EVIDENCE=/tmp/workflow-results.json \
dart run integration_test/workflow_smoke.dart
```

実装CLIによる20呼出しで、template/binding検証、JSON/YAML実行、最終refの別CLI使用、13 charactersへの変化、不存在targetで2step目停止・Tap count 1を確認する。証跡と3枚のPNGを出力する。

W07でタブ往復後の確認を追加し、現在のworkflow_smokeは24呼出しとなる。Controlsはタブから戻ると再生成されるため、入力表示はNot edited、ページ表示はCurrent page 1へ戻る。入力欄が空であることと併せて4枚目のPNGに記録する。

## 追加コマンドのfixture

Advancedタブ（key: `advanced_tab`）に型付き入力・状態・double-tap・hover・キーイベント・drag/drop・mounted offscreen要素を配置する。`lib/advanced_controls.dart`と[追加コマンド仕様](../docs/ja/cli-parity.ja.md)を参照。`marionette_agent_flutter`のdebug providerを登録済みで、`DISABLE_AGENT_EXTENSIONS=true`でstock bindingのみの挙動を検証できる。

## ヘッドレス実行と録画

4環境の必要条件、非表示起動、接続・操作・録画、終了、トラブルシューティングは[ヘッドレス実行と録画](../docs/ja/headless.ja.md)にまとめています。

FFmpegKit native assetsに合わせ、AndroidはAPI 26以上、macOSは13以上を対象とする。iOSは既存の15以上を維持する。録画変換はhost CLI側で行い、アプリのdebug provider登録でFFmpegの初期化は要らない。

## Androidネイティブ撮影fixture

Android debug版のNativeタブ（`native_tab`）に`native_permission`、`native_seedPhoto`（ダミー画像をMediaStoreへ作成）、`native_photoPicker`（API 33以上）、`native_documentPicker`、`native_secureOn`、`native_secureOff`、`native_text_input`を配置する。権限要求・Photo Picker・ACTION_OPEN_DOCUMENT・FLAG_SECUREはAndroidのAPIを使う。カメラは権限ダイアログだけを要求し、撮影や読み取りは行わない。ダミー画像をEmulatorに用意し、OS UIを開いたまま製品CLIのAndroid screenshotで撮影する。secureOffはこのfixture自身のテスト用FLAG_SECUREを解除するためのボタンで、他アプリの保護を変更しない。縦横回転とIME・system barも保存画像で確認する。実機は本Issueの対応・検証範囲外。
