# skill-reflector

AI エージェント (Claude Code / Codex) の Agent Skills を **管理** + **改善** する個人運用ツール。

## 何をするか

| 層 | 担当 |
|---|---|
| **配布層** | [Microsoft APM](https://github.com/microsoft/apm) (Agent Package Manager) に委譲 |
| **agent-skills 入出力** | `/skill-manager` skill が CRUD + sync (内部で apm を呼ぶ) |
| **改善ループ (Reflector)** | セッションログを SQLite に取り込み → cron で headless Claude が分析 → 提案を agent-skills repo に Issue/PR |

skill 本体は別 private repo (`agent-skills`) に APM Skill Collection レイアウト (`skills/<name>/SKILL.md`) で保管。本リポジトリは「仕組み」だけを持つ。

## 構成

```
skill-reflector/
├── client/
│   ├── hooks/
│   │   ├── pre-session.sh   # session start: agent-skills pull + apm install -g --update
│   │   └── post-session.sh  # session end: ログ収集 + scp/cp 送信 (Reflector 入力)
│   └── skills/
│       └── skill-manager/   # /skill-manager skill 本体 (sync, create, list, log, status...)
├── server/                  # Reflector ループ (cron で動かすマシンで有効化)
│   ├── reflector/analyze.md # headless Claude のプロンプト
│   ├── scripts/
│   │   ├── import_logs.py     # JSONL → SQLite
│   │   ├── detect_patterns.py # SQL でパターン抽出 → analysis JSON
│   │   ├── apply_proposals.py # analyze 結果を agent-skills repo に Issue 作成
│   │   └── cron-reflector.sh  # 上記を1日1回実行する entrypoint
│   └── sql/schema.sql
├── docs/notes/              # 設計メモ・移行記録
├── setup.sh                 # 初期セットアップ (apm install -g + skill-manager symlink)
└── .env.sample
```

## セットアップ

1. apm CLI を install:
   ```sh
   curl -sSL https://github.com/microsoft/apm/releases/latest/download/apm-linux-x86_64.tar.gz \
     | tar -xz -C /tmp
   mkdir -p ~/.local/bin && cp /tmp/apm-linux-x86_64/apm ~/.local/bin/
   ```
2. `cp .env.sample .env` して値を埋める
3. `./setup.sh`
4. `~/.claude/settings.json` の hooks に pre/post-session.sh を登録

## 構成パターン (`.env`)

| マシン | `CLIENT_ENABLED` | `SERVER_ENABLED` | 備考 |
|---|---|---|---|
| 作業 PC | true | false | ログを scp で送信 |
| 専用サーバー | false | true | Reflector のみ |
| 1 台完結 | true | true | 全部入り |

## skill 配布の流れ

```
agent-skills (private repo, Skill Collection)
        │
        ├── skills/git-workflow/SKILL.md
        ├── skills/laravel-common/SKILL.md
        └── ...
        │
        ▼  (apm install -g)
~/.claude/skills/        ← cross-cutting global skills (~9個)
        │
        ▼  (各プロジェクトで apm install)
project/.claude/skills/  ← プロジェクト固有 skills (laravel-common など)
```

## Reflector ループ

```
作業マシン x N                 サーバー (cron)
  /skill-manager log         ┌──────────────────────┐
  → ~/.claude/projects/...  │ import_logs.py       │
  → scp で送信 ──────────────┼─→ logs.db (SQLite)  │
                            │ detect_patterns.py   │
                            │ → analysis.json      │
                            │ headless claude      │
                            │ + analyze.md prompt  │
                            │ → proposals.json     │
                            │ apply_proposals.py   │
                            │ → agent-skills に    │
                            │   Issue/PR           │
                            └──────────────────────┘
```

詳細・移行記録: `docs/notes/apm-migration-plan.md`
