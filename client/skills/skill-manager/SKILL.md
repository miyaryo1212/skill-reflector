---
name: skill-manager
description: Manage agent skills — sync, create, list, update, delete, log, status. Use when the user wants to manage their skills or when invoked as /skill-manager.
---

You are skill-manager, the central management skill for skill-reflector.
配布層は `apm` (Agent Package Manager) に委譲し、このスキルは「agent-skills repo への入出力」と「Reflector 系のグルー」を担う。

## Finding the .env file

This SKILL.md は `~/.claude/skills/skill-manager` (または同等の Codex パス) から symlink されている。`.env` の位置は次の手順で解決する:

1. SKILL.md の real path を `readlink -f` で解決
2. そこから上位3階層 (`client/skills/skill-manager/` → repo root) が skill-reflector のインストールルート
3. ルート直下の `.env` を読む

## Subcommands

引数なしで呼ばれた場合は使えるサブコマンドを一覧表示。

### sync

agent-skills repo を pull し、現在のプロジェクトに skill を再インストール。

Steps:
1. `.env` から `SKILLS_LOCAL_PATH` を読む
2. `git -C "$SKILLS_LOCAL_PATH" pull --quiet` (失敗しても続行)
3. プロジェクトルートに `apm.yml` が無ければ:
   - 旧 `.skill-reflector.yaml` の有無を確認し、あれば「`apm.yml` への移行を勧める」とユーザーに伝える
   - その後は何もしない (apm.yml が無いプロジェクトでは sync 対象なし)
4. `apm.yml` がある場合: `apm install --update --target claude` を実行
   - Codex も使うプロジェクトでは `--target claude,codex` を案内
5. 結果を簡潔に報告 (deployed skill 数とパス)

### create

新規 skill を作成し agent-skills repo へ PR を出す。

Steps:
1. ユーザーに尋ねる: skill 名、description、対象スコープ (グローバル / 特定プロジェクト用)
2. `<skill-reflector-repo>/client/templates/skill-template.md` をテンプレに `SKILL.md` を生成
   - `name:` はディレクトリ名と一致させる (Agent Skills 標準)
   - プロジェクト固有 skill は `<context>-<skill>` 形式の名前を推奨 (例: `laravel-common`, `agent-sentinel-add-target`)
3. `$SKILLS_LOCAL_PATH/skills/<name>/` にディレクトリ作成して配置
4. agent-skills repo で feature branch を切り、commit、push
5. `gh pr create` で PR
6. PR 作成後、現プロジェクトの `apm.yml` に依存追加が必要か確認・案内
   ```yaml
   dependencies:
     apm:
       - <SKILLS_LOCAL_PATH>/skills/<name>
   ```

### list

管理下の skill 一覧を表示。

Steps:
1. `.env` から `SKILLS_LOCAL_PATH` を取得
2. `$SKILLS_LOCAL_PATH/skills/` 配下の全 SKILL.md を列挙
3. 現プロジェクトの `apm.yml` または `apm.lock.yaml` を読み、どれが install 済みか判定
4. テーブルで表示: `name | description (1行) | installed?`

### update

既存 skill を編集する。

Steps:
1. ユーザーが対象 skill を選択 (list を裏で実行)
2. `$SKILLS_LOCAL_PATH/skills/<name>/SKILL.md` を読み込み、変更内容をユーザーと協議
3. ファイルを編集
4. agent-skills repo で feature branch を切り、commit、push、`gh pr create`

### delete

skill を削除する。

Steps:
1. ユーザーが対象 skill を選択し、削除を確認
2. agent-skills repo で feature branch を切り、`git rm -r skills/<name>` → commit、push
3. `gh pr create` で PR
4. 当該 skill に依存していたプロジェクトの `apm.yml` をユーザーに伝え、依存削除を案内

### log

現在のセッションログを記録・送信する (Reflector の入力)。

Steps:
1. `.env` から `LOG_SERVER`, `LOG_SERVER_PATH`, `MACHINE_NAME`, `SERVER_ENABLED` を取得
2. 現セッションのログファイルを特定:
   - Claude Code: `~/.claude/projects/<project>/` の最新 `.jsonl`
   - Codex: `~/.codex/sessions/YYYY/MM/DD/` の最新 `rollout-*.jsonl`
3. 構造化ファイル名生成: `<MACHINE_NAME>_<timestamp>.jsonl`
4. モードに応じて配置:
   - `SERVER_ENABLED=false`: `scp <logfile> $LOG_SERVER:$LOG_SERVER_PATH/$MACHINE_NAME/`
   - `SERVER_ENABLED=true`: `cp <logfile> $LOG_SERVER_PATH/$MACHINE_NAME/`
5. 結果を報告

### status

現プロジェクトの skill-reflector + apm 状態を表示。

Steps:
1. 検出したエージェント (Claude Code / Codex) を表示
2. `.env` の主要設定を要約
3. `apm.yml` の有無と依存数、`apm.lock.yaml` の version
4. グローバル symlink 経由で見える skill 数 (`~/.claude/skills/` を走査)
5. 旧 `.skill-reflector.yaml` がまだ残っていれば「Phase 5 で削除予定」と注記
6. 直近の log 送信タイムスタンプ (`SERVER_ENABLED=false` 時は scp ログ確認)
