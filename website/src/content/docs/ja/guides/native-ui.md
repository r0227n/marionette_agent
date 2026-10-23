---
title: ネイティブダイアログと写真ピッカー
description: 権限許可や写真選択を含むiOS Simulator・AndroidのOS画面をmarionette-agentから操作します。
---

権限ダイアログやOSの写真ピッカーがFlutter画面を覆ったら、`native`を使います。選択した端末の前面画面を、Flutter VMへの接続なしで操作できます。通常のFlutterコマンドと同じsessionでも利用できます。

## 端末を準備する

macOS上のiOSの観測・入力には、daemonの`PATH`で動作する`idb`と`idb_companion`が必要です。撮影にはXcodeの`xcrun simctl`を使います。iOS Simulatorが対象で、iOS実機は対象外です。[idbの導入手順](https://fbidb.io/docs/installation/)を参照してください。AndroidにはAndroid SDKの`adb`と、認証済み・online状態のEmulatorまたは実機が必要です。Computer連携やアプリ側のネイティブテストrunnerは不要です。

```sh
marionette-agent device list --platform ios
marionette-agent device list --platform android
```

普段のプロジェクトの手順で端末とdebugアプリを起動します。`--device`には必ずiOSのUDIDまたはAndroidのserialを指定してください。端末の自動選択・起動、ツールのインストール、権限の無断付与は行いません。端末ごとに操作担当を1つにしてください。同じdaemon内では端末単位でネイティブ操作を直列化しますが、別runtimeや外部の操作担当とは独立しています。

## 権限ダイアログを観測して応答する

`IOS_UDID`を実際の端末IDへ置き換えます。応答を選ぶ前に実際のラベル・refを確認してください。ボタンの表示はOSや言語で変わります。

```sh
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app native screenshot ./permission.png --platform ios --device IOS_UDID
marionette-agent --session app native tap --text 'Allow' --platform ios --device IOS_UDID
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
```

Androidではplatformとserialを置き換えます。snapshotに表示されたpermission controllerのresource IDは、`--identifier`で完全一致選択できます。

```sh
marionette-agent --session app native snapshot --platform android --device emulator-5554
marionette-agent --session app native tap @n1 --platform android --device emulator-5554
marionette-agent --session app native screenshot ./android-result.png --platform android --device emulator-5554
```

`@n1`は例です。必ず最新のnative snapshotが返したrefを使ってください。ネイティブrefはsession・端末に紐づき、Flutterの`@e`とは別です。tapの対象はネイティブref、完全一致の`--text`・`--identifier`・`--type`、または明示的な`--x`/`--y`のいずれか1つです。ラベルが複数一致すればtapせず失敗します。refでのtap直前には要素の属性・boundsを再確認し、観測した中心を1回だけtapします。移動・変更した要素は`STALE_REF`です。

## 写真を選んでFlutterへ戻る

Flutterの`snapshot`で確認した対象を通常の`tap`で操作し、ピッカーを開きます。OS画面は`native snapshot`で確認します。iOSのOS側で表示される写真ピッカーには、idbからアプリのrootしか取得できないものがあります。native snapshotの成功は、見えている全コントロールの取得を意味しません。子要素を取得できない場合は`limitation`に説明を返します。

選びたい対象にrefがなければ、`native screenshot`を取得して画像を確認し、意図した座標を明示します。不存在・失効refから座標tapへの自動fallbackは行いません。

```sh
marionette-agent --session app native screenshot ./picker.png --platform ios --device IOS_UDID
marionette-agent --session app native tap --x 67 --y 379 --platform ios --device IOS_UDID
marionette-agent --session app snapshot
marionette-agent --session app screenshot ./selected-image.png
```

座標は例であり、現在の画面から選び直してください。iOSは**画面のpoint**、Androidは**画面のpixel**を使います。結果の`coordinateSpace`に単位を返します。iOSの撮影画像はpointよりpixel数が多い場合があるため、nativeのアプリboundsと画像寸法で各軸を換算します。402×874 pointの画面が1206×2622 pixelの画像なら、画像座標を3で割ります。Flutter座標をネイティブUIへ流用したり、回転後に座標を再利用したりしないでください。入力座標はplatformツールに合わせて整数へ丸めます。

ピッカー内を移動するときは、指の移動座標を指定して結果を観測します。

```sh
marionette-agent --session app native swipe --start-x 200 --start-y 700 --end-x 200 --end-y 350 --platform ios --device IOS_UDID
marionette-agent --session app native screenshot ./picker-scrolled.png --platform ios --device IOS_UDID
```

写真選択後はFlutterのsnapshotと画像の両方を確認し、ピッカーが閉じて選択した内容がアプリへ表示されたことを検証します。iOS Simulatorでは権限を許可してもカメラ機器は追加されないため、アプリがカメラなしを報告する場合があります。

## 結果・証跡・終了

native snapshotは`source: native`、platform、device、座標単位、generation、bounds付きの正規化要素を返します。`--json`、`--content-boundaries`、`--max-output`、期限、通常のエラー包絡を適用します。native screenshotはOSの重なった画面を含み、PNG/JPEG設定・上書き防止・保存先の規則は通常のscreenshotと共通です。ネイティブUIを録画する場合は端末の`record --platform ios|android`を使います。Flutter描画の録画には含まれません。

native tap/swipeは同じ端末のネイティブrefをsession横断で失効させ、同じdaemon内の全Flutter snapshotも保守的に失効させます。Flutter操作はそのsessionのnative refを失効させます。操作後は毎回観測し直してください。別端末のnative screenshotを撮った場合も、そのsessionの旧native refは失効します。nativeの読み取りは非変更操作で、action policyではtap/swipeを`native`として制御します。送信後の失敗・timeoutは`outcome: unknown`です。次の判断前に画面を確認し、自動再送しないでください。

MCPでは`--tools core,native,record`を指定できます。native profileは`marionette_agent_` prefix付きの`native_snapshot`・`native_tap`・`native_swipe`・`native_screenshot`を公開します。毎回platformとdeviceを指定し、native targetには`@n` ref・text・identifier・typeを使います。native screenshotもinline画像を返します。nativeはbatch・workflow v1には含めません。

```sh
marionette-agent --session app record stop
marionette-agent --session app close
```

closeはsessionとrefを解放します。外部起動したアプリ・端末・idbが管理するcompanionの寿命は独立しているため、自分のrunnerと検証端末を別途終了・解放してください。
