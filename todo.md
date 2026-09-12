# Issue #13 進捗

担当: gpt-6-astra / xhigh（Issue #13専任worker）。着手時のAGENTS.mdにtodo.mdの指定はなく、既存todo.mdもなかったため、本ファイルを入口として整備した。詳細な受入対応・検証結果・再現手順は[Issue #13検証記録](packages/marionette_agent/docs/verification/issue-13.md)に記録する。

- [x] 共通オプションへPNG/JPEG形式とJPEG品質を追加
- [x] 白背景合成・拡張子・自動名・複数画像・元の期限・排他的保存を実装
- [x] SPEC・ARCHITECTURE・日本語CLIリファレンス・help更新
- [x] format / analyze / 関連test（concurrency=1）
- [x] 全test（concurrency=1、179件成功）
- [x] 専用Simulatorで製品CLIのtext/JSONと実画面を確認し、全選択画像を開く
- [x] 所有session・daemon・runner・appの終了、専用SimulatorのShutdown、資源解放確認
- 公開・再読結果はGitHubのdevelop宛Draft PRと`/private/tmp/mra-p2-20260912/worker-13-result.md`へ記録する。
- [ ] 人間による動作確認

状態: Agent検証完了、人間確認待ち。2026-09-13、実装commit `3bf0d26c2bd10435e4f4a69514837d17bbe0a7ee`の全体179 tests、53回の製品CLI呼出し、全14画像の確認、専用資源の終了とShutdownを確認済み。Draft PRで引き渡し、人間確認は未実施として残す。

統合注意: Issue #12もscreenshot周辺を変更する。共通オプション・parser・runner・artifact writer・画像テスト・同じ仕様書が競合候補。このbranchは指定develop基点からIssue #13だけを実装し、他Issueのmerge/cherry-pick/stackは行っていない。
