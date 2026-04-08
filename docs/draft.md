# skill-reflector 構想

Claude Code や Codex のような AI エージェントの Agent Skills を一括で管理、改善する仕組みの検討。
両ツールとも Agent Skills のオープン標準 (`SKILL.md` + YAML frontmatter) に準拠しており、共通の仕組みで対応可能。

## ターゲット

|   | エンジニア (Claude Code) | 非エンジニア (Claude CoWork等) |
| --- | --- | --- |
| Skills管理 | GitHub repo | プラットフォーム側の機能に委ねる |
| 改善提案 | PR / Issues | スコープ外 |
| 同期 | git pull | - |

→ まずはエンジニア / Claude Code・Codex にフォーカスして開発する

### 対応エージェントの比較

| | Claude Code | Codex |
| --- | --- | --- |
| グローバル skills | `~/.claude/skills/` | `~/.codex/skills/` |
| プロジェクト skills | `.claude/skills/` | `.agents/skills/` |
| ファイル形式 | `SKILL.md` (YAML frontmatter + Markdown) | 同左 |
| セッション保存 | `~/.claude/projects/<project>/<id>.jsonl` | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| セッション構造 | プロジェクトベース | 日付ベース |
| 設定ファイル | `settings.json` (JSON) | `config.toml` (TOML) |
| hooks | あり (pre/post) | なし |

#### エージェント差異の吸収方針

- **skills 管理**: 共通 (`SKILL.md` 形式)。symlink 先パスだけエージェントごとに分岐
- **ログ収集**: セッション履歴のパスと構造が異なる。`skill-manager log` 内でエージェントごとにパス解決を分岐。JSONL 形式は共通なので解析ロジックは共通化可能
- **hooks**: Claude Code のみ。hooks がないエージェントは手動実行で同等機能を提供
- **設定ファイル操作**: skill-reflector 自身の `.env` は共通。エージェント側の設定書き換えは hooks 登録時 (Claude Code) のみ必要

## リポジトリ構成

2つのリポジトリに分離する。

### skill-reflector (public) — 仕組み・ツール本体

client/server に分離。マシンごとに有効/無効を切り替えて使う。

```
skill-reflector/
  ├── client/
  │   ├── commands/
  │   │   └── skill-manager.md     # 管理skill本体
  │   ├── hooks/
  │   │   ├── pre-session.sh       # skills sync
  │   │   └── post-session.sh      # ログ記録 + 送信
  │   └── templates/
  │       └── skill-template.md    # skill作成テンプレート
  │
  ├── server/
  │   ├── reflector/
  │   │   ├── analyze.md           # 分析用プロンプト
  │   │   └── config.yaml          # cron設定等
  │   └── scripts/
  │       ├── import-logs.sh       # JSON → SQLite取り込み
  │       └── cron-reflector.sh    # daily cron エントリポイント
  │
  ├── .env.sample
  ├── docs/
  └── README.md
```

### agent-skills repo (private) — 個人の skills 実体

ユーザーが別途用意する private リポジトリ。`.env` で指定する。
skills は global（全プロジェクト共通）と namespaces（技術領域ごと）に分類する。

```
agent-skills/
  ├── global/              # 全プロジェクト共通
  │   ├── commit-ja.md
  │   └── review-pr.md
  └── namespaces/          # 技術領域ごとの名前空間
      ├── rails/
      │   ├── migrate.md
      │   └── generate.md
      ├── docker/
      │   └── compose-up.md
      └── aws/
          └── deploy-ecs.md
```

プロジェクト側に `.skill-reflector.yaml` を配置し、必要な名前空間を宣言する。

```yaml
# project-x/.skill-reflector.yaml
namespaces:
  - rails
  - docker
```

### 環境設定 (.env)

1つの `.env` で client/server それぞれの有効/無効を切り替える。

```bash
# === Skills設定 ===
SKILLS_REPO=git@github.com:your-name/agent-skills.git
SKILLS_LOCAL_PATH=~/.skill-reflector/agent-skills

# === Client機能 (有効: true / 無効: false) ===
CLIENT_ENABLED=true
LOG_SERVER=user@server.example.com
LOG_SERVER_PATH=~/.skill-reflector/logs
MACHINE_NAME=machine-a

# === Server機能 (有効: true / 無効: false) ===
SERVER_ENABLED=false
DB_PATH=~/.skill-reflector/logs.db
CRON_SCHEDULE="0 3 * * *"
AUTO_REFLECTION=false     # true: PRを自動マージ / false: 提案止まり
```

#### 構成パターン

| マシン | CLIENT | SERVER | 備考 |
| --- | --- | --- | --- |
| 作業PC | true | false | ログをサーバーに送るだけ |
| 専用サーバー | false | true | Reflector のみ |
| 1台完結 | true | true | 全部入り |

## アーキテクチャ概要

```
  skill-reflector (public)     agent-skills repo (private)
  仕組み・hooks・プロンプト     skills実体 (global/namespaces)
         │                            │
         │    /skill-manager sync     │
         │    → agent-skills を pull   │
         │    → symlink 作成          │
         ▼            ▼               ▼
  各プロジェクト
    ~/.claude/commands/        ← global skills
    .claude/commands/          ← .skill-reflector.yaml で指定した namespaces

  Machine A (作業マシン)        Machine B (作業マシン)
    /skill-manager log            /skill-manager log
    (Claude Code: post hookで自動) (手動 or post hook)
    → 生ログを構造化データで記録    → 生ログを構造化データで記録
    → scp で送信                  → scp で送信
        │                             │
        └────────────┬────────────────┘
                     ▼
          Server (定期実行マシン)
          ~/.skill-reflector/
            ├── logs/
            │   ├── machine-a/    # 構造化ログ
            │   └── machine-b/
            └── logs.db           # SQLite (分析用)
                     │
                     │ cron (daily headless Claude)
                     │ → ログ要約 + 分析
                     ▼
          GitHub: agent-skills repo へ Issues / PR として提案
```

## 主要機能

### 1. Skills の一元管理

- skills の実体は private な agent-skills repo で管理
- skill-reflector 本体 (public) と分離 → OSS 化可能
- バージョン管理・変更履歴・ロールバックが自然にできる
- チーム共有は agent-skills repo を org repo にするだけ

### 2. skill-manager (skill の CRUD・管理を集約する skill)

skill の作成・管理操作を `/skill-manager` に一元化する。
skills の実体は常に agent-skills repo に置き、ローカルには symlink で反映する。
全サブコマンドは手動実行が基本。Claude Code の場合は hooks で自動化できる。

- `create` — 新規 skill 作成 → agent-skills repo へ PR + ローカルに symlink
  - 作成後、skills ディレクトリをスキャンし未登録 skill があれば登録を提案
- `list` — skills 一覧表示 (repo 管理 / 未登録の区別付き)
- `update` — 既存 skill 編集 → agent-skills repo へ PR
- `delete` — skill 削除 → agent-skills repo へ PR + symlink 除去
- `sync` — agent-skills repo を pull + `.skill-reflector.yaml` に基づき symlink 再構築
- `log` — セッションの生ログを記録・送信
- `status` — 現在のプロジェクトの skill 状態確認

プロジェクトごとに `.skill-reflector.yaml` で使用する namespaces を宣言し、各プロジェクトの git に含める。

### 3. Hooks による自動化 (Claude Code 向けオプション)

hooks がないエージェント (Codex 等) でも手動で `/skill-manager sync` `/skill-manager log` を実行すれば同等の機能が使える。
Claude Code の場合は hooks で自動化し、より良い UX を提供する。

**セッション開始時 (Pre hook)**

- `/skill-manager sync` を自動実行
  - agent-skills repo を git pull
  - `.skill-reflector.yaml` に基づき symlink を再構築 (global + 指定 namespaces)
  - 失敗時 (オフライン等) はブロックせず続行

**セッション終了時 (Post hook)**

- `/skill-manager log` を自動実行
  - セッションの生ログを軽量な構造化データとして記録
  - 送信方法はモードで切り替え:
    - 作業PC (`SERVER_ENABLED=false`): scp でサーバーへ送信
    - 1台完結 (`SERVER_ENABLED=true`): ローカルのログディレクトリに直接書き込み

### 4. Reflector (分析・提案エンジン)

- headless Claude を毎日定刻に実行 (cron)
- skill-reflector 本体のアップデートチェック → 更新があればスクリプト実行
- 蓄積されたログをまとめて要約・分析し、GitHub Issues / PR として起票:
  - **新規 skill 化提案**: skill 未使用セッションの繰り返しパターンを検出
  - **skill 分割提案**: 肥大化した skill の分割案
  - **skill 改善提案**: 既存 skill の使われ方に基づく改善案
- `AUTO_REFLECTION=false` (デフォルト): 提案止まり → ユーザーがレビュー・マージ
- `AUTO_REFLECTION=true`: PR を自動マージ → 次の sync で反映

## ログ戦略

全セッションのログを収集する (skill 使用/未使用問わず)

- **skill 使用セッション** → 改善・分割のヒント
- **skill 未使用セッション** → 新規 skill 化の候補 (まだ skill 化されていない作業パターンの宝庫)

post hook では生ログの記録・送信のみ。要約・分析はサーバー側の Reflector が定刻にまとめて実行する。
API コストは Reflector の定刻実行時のみ発生。

## 未決事項

- [ ] Skills のフォーマット: Claude Code の `.md` そのまま vs 独自フォーマット + エクスポート
- [x] ~~CLI の具体的なコマンド体系~~ → skill-manager に集約
- [ ] Reflector のプロンプト設計
- [ ] ログの保持期間・ローテーション
- [ ] 機密情報の sanitize ルール
