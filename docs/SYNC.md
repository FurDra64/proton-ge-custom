# Upstream Sync 契約 (v1)

## 追従対象
- Primary: `GloriousEggroll/proton-ge-custom` の `master` ブランチに日次追従。
- タグ (`GE-Proton*`) 追従はしない (v1 の範囲外。将来 `upstreams.yml` に追加で対応)。

## 統合方式: merge (rebase しない)
- 理由: `master` は共有ブランチ。rebase は SHA を書き換える破壊的操作で、
  他の作業者・進行中の PR を壊す。共有線は merge のみ (git-workflows 知識)。
- 自動処理が `master` に直接 push することは**禁止**。
  成功時も `sync/upstream-*` ブランチ → PR 経由で人間がマージする。
- `git push --force` 禁止。`--force-with-lease` も sync 系では使わない。

## 失敗の2層 (両方を見る)
1. **git 層**: `upstream/master` の merge がコンフリクトするか。
2. **patch 層**: `patches/protonprep-valve-staging.sh` の適用が失敗するか
   (`patchlog.txt` に fail/error が出るか)。
- git 層が成功しても patch 層で壊れることがあるため、
  「merge 成功 = 緑」と誤認しない。v1 スケルトンは git 層のみを判定し、
  patch 層は Phase 2 で追加する。

## conflict 時の挙動 (v1)
- **Issue 起票が正**。コンフリクト状態のまま PR を作ってもマージ不可で
  CI ビルドも回せず、運用が詰まるため。
- ただし差分が自明ファイルのみ (`VERSION`, `*.md`, `compatibility-report.md`,
  `*.vdf.template`, `*.sample.py`) の場合は workflow 自身が upstream 側を採用して
  解決し、`automerge-trivial` ラベル付き PR を作る (AI 自動解決の安全な部分集合)。
- それ以外は `upstream-sync`, `conflict` ラベル付き Issue を起票し、
  手動解決 (将来は Issue コメント起点で AI 解決を起動できる形にする)。
- Issue には必ず含める: upstream SHA / base SHA / behind 件数 /
  コンフリクトファイル一覧 / 直近の upstream ログ (10件)。

## 複数 fork 吸収 (Phase 2 以降)
- `upstreams.yml` の manifest に源泉を追加する形で拡張する。
  優先順位: primary (GE) → secondaries (CachyOS 等)。
  secondaries は primary への適用が通った後に順次 cherry-pick/merge する。
- v1 では primary 1件のみ有効。CachyOS 欄は雛形 (enabled: false)。

## 運用
- 実行: 毎日 JST 03:00 (cron `0 18 * * *`) + 手動 `workflow_dispatch`。
- 冪等性: 追従不要 (behind=0) のときは何も作らず summary のみで終了する。
- 通知の重複防止: 同一 upstream SHA に対する open な Issue/PR があれば再作成しない。
