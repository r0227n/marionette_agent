# Issue #8 進捗

- 担当: Astra（割当: gpt-6-astra / xhigh、単独worker）
- Branch: `feature/issue-8-environment-defaults`
- Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`)
- 着手時に既存todo.md／Issue #8記録がないことを確認し、本記録を整備。
- [x] 共通オプションの環境fallback、help、SPEC、ARCHITECTURE、日本語CLIリファレンス
- [x] 環境を隔離したparser／CLIテストを追加
- [ ] format、analyze、関連test、全test（concurrency=1）
- [ ] 割当Simulatorで製品CLI・text/JSON・操作後画像を確認し終了処理
- [ ] 検証済みdevelop宛Draft PR、画像添付、人間の再現手順
- [ ] 人間による確認

検証コマンド、期待／実際の結果、対象commit、エビデンスは [Issue #8検証記録](packages/marionette_agent/docs/verification/issue-8.md) へ記録する。

統合時の注意: #12・#13とは独立したdevelop基点で実装する。screenshot本体は変更しない。共通parser/helpとSPEC・ARCHITECTURE・日本語CLIリファレンスに統合時の競合候補がある。他Issueの実装を取り込まない。
