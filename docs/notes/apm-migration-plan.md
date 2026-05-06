# apm 移行計画

`microsoft/apm` (Agent Package Manager) への移行検討メモ。

## 背景

- skill-reflector の「配布レイヤ」（pull + symlink）は apm がカバーする領域とほぼ重複
- 「Reflector ループ」（log 収集 → cron 分析 → PR 提案）は apm スコープ外 = **独自価値として存続**
- agent-skills repo の SKILL.md は既に Anthropic Agent Skills 標準準拠なので、ファイル中身の改変は **不要**
- 方針: **配布層は apm に剥がす / Reflector は残す** のハイブリッド

## フォーマット互換性まとめ

| 層 | 採用 |
|---|---|
| Skill 単体 (atom) | Agent Skills 標準 SKILL.md（変更なし） |
| 複数 skill の束ね | **APM Skill Collection** (`skills/<name>/SKILL.md` + `apm.yml`) |
| 将来の marketplace 配布 | Claude Code Plugin (`.claude-plugin/plugin.json`) を後乗せ |
| Reflector の PR 先 | SKILL.md ファイル直（パッケージ層に依存しない） |

## 移行サーフェス（実測）

| カテゴリ | 量 | 備考 |
|---|---|---|
| agent-skills の SKILL.md | 14個 (global 9 + namespaces 5) | frontmatter 全て標準準拠 |
| consumer プロジェクト | 3個 (agent-sentinel / skill-reflector / trend-research) | `.skill-reflector.yaml` は各1-2行 |
| `~/.claude/skills/` symlink | 9本 | 一括張替え対象 |
| skill-manager skill | 115行 | sync/create/list/update/delete を apm へ委譲、log/status は残す |
| pre-session.sh | 39行 | `apm install` 1行に縮約 |
| post-session.sh | 61行 | **不変**（Reflector 経路） |
| Reflector 本体 (Python+prompt) | 911行 | **不変**。PR テンプレのパス記述だけ更新 |
| setup.sh | 78行 | スクラップ寄り |

## Phase 0 〜 5 概要

| Phase | 状態 | 目的 | 主な作業 | 工数 |
|---|---|---|---|---|
| **0. PoC 検証** | ✅ 完了 | 移行可否を確定させる判断材料を作る | apm 実機インストール、`--target claude/codex/agent-skills` の展開先確認、local path: dep の構文確認、global vs project-local 挙動の実測 | 0.5日 |
| **1. agent-skills repo 再構成** | ✅ 完了 (PR #40) | APM Skill Collection 化 | `global/` → `skills/` rename、`namespaces/` の扱い決定、`apm.yml` 追加（10行） | 2-3h |
| **2. Consumer 3 プロジェクト移行** | ✅ 完了 | 各プロジェクトを apm install 駆動に | `.skill-reflector.yaml` → `apm.yml` 書き換え、apm install で動作確認 | 2-3h |
| **3. skill-manager / hooks 縮小** | ⏳ 未着手 | apm CLI に委譲できる部分を削減 | pre-session.sh を `apm install` に短縮、skill-manager の CRUD サブコマンドを薄ラッパーに（115→50行ほど）、log/status は残す | 0.5-1日 |
| **4. Reflector 出力先調整** | ⏳ 未着手 | PR が apm 規約に従うように | analyze.md プロンプトのパス更新、apply_proposals.py の PR パス変更、(任意) apm.yml version bump 化 | 2-3h |
| **5. クリーンアップ** | ⏳ 未着手 | 旧仕組みの撤去とドキュメント | 旧 symlink 9本除去、readme 更新、`.skill-reflector.yaml` 削除、setup.sh 退避 | 2-3h |

### Phase 1 + 2 の実施記録

**Phase 1** (agent-skills repo, 2026-05-07):
- `global/` → `skills/`、`namespaces/<ns>/<name>/` → `skills/<ns>-<name>/` (flat 化)
- `add-target` / `update-history` の `name:` フィールドをディレクトリ名に整合
- ルートに `apm.yml` 追加
- PR #40 マージ済み
- `~/.claude/skills/` の 8 symlink を新パス (`agent-skills/skills/`) に張替え

**Phase 2** (consumer 3 プロジェクト, 2026-05-07):
| プロジェクト | 主な変更 | コミット先 |
|---|---|---|
| skill-reflector | `apm.yml` (python-common 依存)、`.gitignore` に `apm_modules/` | main 直 (`057267e`) |
| trend-research | `apm.yml` (trend-research-update-history 依存)、旧 dot-symlink 削除 | (git管理外) |
| agent-sentinel | `apm.yml` (agent-sentinel-add-target 依存)、`.claude/` を `.gitignore`、旧 dot-symlink 削除 | `feature/add_skill_reflector_config` (`af81f5f`) |

各プロジェクトで `.skill-reflector.yaml` は **意図的に残置** (Phase 5 cleanup で削除予定)。
旧 hook の動作 (git pull のみ) と並行運用しても干渉なし。

**合計: 3日 ± 1日**（実コーディング時間ベース、待ち時間除く）

## レンジを広げるリスク

| リスク | 影響 | 解消条件 |
|---|---|---|
| `apm install --target claude` がプロジェクトローカルのみ対応の可能性 | +0.5〜1日 (user-scope の代替策設計) | Phase 0 で `apm install -g --target claude` 実挙動測定 |
| `compile -t codex` が `~/.codex/skills/` まで届かない可能性 | +2-3h (簡易グルー追加) | Phase 0 で codex で 1 skill 試行 |
| `namespaces/` の APM 表現方式（subpackage vs flat） | +2-3h (flat 化なら命名衝突回避) | Phase 0 で `--skill <name>` selective install 試行 |
| apm 自体の破壊的変更（若いツールゆえ） | スコープ外、運用後再評価 | — |

## スコープ外（移行しない / 触らない）

- SKILL.md コンテンツ
- Reflector コアロジック（Python 799行）
- 新規 skill 開発
- apm 自体への contribution

---

## 目前の実行計画 (Phase 0)

**目的**: 上記リスク3つを潰し、残り Phase 1-5 の総量を 2日 / 3日 / 4-5日 のどれに確定するか決める。

### 作業ブランチ

```
git switch -c feature/apm-migration-poc
```

PoC 用のサンドボックスは別ディレクトリ:
```
~/tmp/apm-poc/
  ├── sandbox-skills/        # agent-skills 構造の copy
  └── sandbox-consumer/      # consumer プロジェクトの仮想再現
```

### ステップ

1. **apm インストール**
   ```sh
   curl -sSL https://aka.ms/apm-unix | sh
   apm --version
   ```

2. **agent-skills を APM Skill Collection 形式で複製**
   - `~/.skill-reflector/agent-skills/` → `~/tmp/apm-poc/sandbox-skills/` にコピー
   - `global/` → `skills/` に rename
   - ルートに最小 `apm.yml` を置く:
     ```yaml
     name: agent-skills
     version: 0.1.0
     ```
   - `apm pack` が通るか確認

3. **target 別の install 先を実測**

   `~/tmp/apm-poc/sandbox-consumer/` で:
   ```sh
   apm install ../sandbox-skills --target claude
   apm install ../sandbox-skills --target codex
   apm install ../sandbox-skills --target agent-skills
   ```
   → それぞれの展開先（パス、ファイル数、symlink/copy のどちらか）を記録。

4. **global install 検証**（最大の不確定要素）
   ```sh
   apm install -g ./sandbox-skills --target claude       # ~/.claude/skills/ に来るか?
   apm install -g ./sandbox-skills --target agent-skills # ~/.agents/skills/ に来るか?
   ```
   → Claude Code から実際に skill が見えるか `claude` 起動して確認。

5. **local path 依存の構文確認**
   sandbox-consumer の `apm.yml` に:
   ```yaml
   dependencies:
     apm:
       - ../sandbox-skills
       - ../sandbox-skills/skills/git-workflow
   ```
   → `apm install` がローカルパスを解決するか、devDependencies の挙動はどうか。

6. **selective install 試行**（namespaces 戦略決定）
   ```sh
   apm install ../sandbox-skills --skill git-workflow --skill ssh-hosts
   ```
   → 一部 skill だけ install できるか、namespaces をサブディレクトリで扱った場合の挙動。

7. **Codex 互換確認**
   - codex CLI で sandbox-consumer に対して skill が見えるか
   - 見えない場合はパスをメモして手動コピーで埋まるか確認

### 完了条件 (Go/No-Go ライン)

| 確認項目 | OK ライン |
|---|---|
| Claude Code が installed skill を認識する | `/help` または skill listing で見える |
| Codex が installed skill を認識する | 同上 |
| local path 依存が解決される | `apm install ./local-path` がエラーなく完走 |
| global install の現実解がある | `~/.claude/skills/` 直書き or symlink 一段噛ます方式が動く |
| namespaces を表現できる | subpackage か flat か、どちらかが回る |

5/5 通れば全 Phase 進行。3-4/5 で残り Phase の見積もり再評価。2/5 以下なら apm 採用は半年見送り。

### 成果物

- `docs/notes/apm-poc-result.md` に上記の実測結果と Go/No-Go 判断を記録
- 通った場合は `docs/notes/apm-migration-plan.md` (本ファイル) を Phase 1 用の確定計画に書き換える

### 想定所要時間

**3-4時間**。失敗時の調査 + Issue/discussion 投稿で +2-3h の可能性あり。
