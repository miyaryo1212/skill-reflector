# apm (Agent Package Manager) 導入と使い方

[`microsoft/apm`](https://github.com/microsoft/apm) は AI エージェント (Claude Code / Codex / Cursor / Copilot 等) の Agent Skills を、**npm のように依存解決 + ロックファイルで管理** できる CLI。
本ドキュメントは Claude Code 利用者向けの最短導入 + 日常運用ガイド。

## なぜ使うか

| 問題 | 旧来のやり方 | apm |
|---|---|---|
| skill を複数プロジェクトで共有 | symlink を手で張る | `apm.yml` に依存宣言 |
| バージョン pin / ロールバック | git tag 手運用 | `apm.lock.yaml` 自動生成 |
| マルチエージェント対応 | パス分岐スクリプト | `--target claude,codex,...` |
| 配布 | git pull する README に書く | marketplace / 任意 git host |
| 監査 | なし | `apm audit` |

要するに **「skill 配布の npm」**。エージェント間で共通の SKILL.md フォーマット (Anthropic 標準) をそのまま運ぶ仕組み。

## インストール

公式インストーラは sudo で `/usr/local/bin` に書く挙動なので、`~/.local/bin` 派は手動展開を推奨:

```sh
mkdir -p ~/.local/bin
cd /tmp
curl -sSL https://github.com/microsoft/apm/releases/latest/download/apm-linux-x86_64.tar.gz | tar -xz
cp -r apm-linux-x86_64/apm apm-linux-x86_64/_internal ~/.local/bin/
~/.local/bin/apm --version    # → Agent Package Manager (APM) CLI version 0.x.x
```

公式手順がよければ:
```sh
curl -sSL https://aka.ms/apm-unix | sh   # /usr/local/bin に sudo install
brew install microsoft/apm/apm           # macOS
pip install apm-cli                       # pip 派
```

## 基本コンセプト

apm は agent-skills repo を **3 種類の package layout** として認識する。最も普通なのは **Skill Collection**:

```
agent-skills/                    ← repo root
├── apm.yml                      ← package metadata (name + version)
└── skills/
    ├── git-workflow/SKILL.md    ← skill 1個 = 1 ディレクトリ
    ├── ssh-hosts/SKILL.md
    └── laravel-common/SKILL.md
```

**SKILL.md 自体は変更不要**。Anthropic Agent Skills の標準フォーマットがそのまま使える:
```markdown
---
name: git-workflow                       # ディレクトリ名と一致必須
description: Git branching strategy...   # 1024字以内
---

ここに skill 本体の指示...
```

## プロジェクト単位の使い方 (一番よく使う)

### 1. プロジェクトに `apm.yml` を置く

```yaml
# project/apm.yml
name: my-project
version: 0.1.0
dependencies:
  apm:
    # ローカルパス、git URL、shorthand (owner/repo) どれでも OK
    - /path/to/agent-skills/skills/git-workflow
    - /path/to/agent-skills/skills/laravel-common
```

shorthand 形式:
```yaml
dependencies:
  apm:
    - anthropics/skills/skills/frontend-design       # github
    - microsoft/apm-sample-package#v1.0.0            # tag pin
    - gitlab.com/org/repo                            # 他 host
```

### 2. install

```sh
cd project/
apm install --target claude          # → .claude/skills/<name>/ に展開
apm install --target codex           # → .agents/skills/<name>/ に展開
apm install --target claude,codex    # 同時に両方
```

`apm.lock.yaml` が生成され、commit SHA で再現性が保証される。`apm_modules/` (キャッシュ) は自動で `.gitignore` 入り。

### 3. 更新

```sh
apm install --update                 # latest の commit に更新 (lockfile 書き換え)
apm install                          # lockfile pinned のまま、念のため再展開
```

## グローバル skills (全プロジェクトで使うやつ)

`~/.apm/apm.yml` を作って `-g` フラグ:

```yaml
# ~/.apm/apm.yml
name: yourname
version: 1.0.0
dependencies:
  apm:
    - /path/to/agent-skills/skills/git-workflow      # cross-cutting なやつだけ
    - /path/to/agent-skills/skills/secure-credential
    - /path/to/agent-skills/skills/ssh-hosts
```

```sh
apm install -g --target claude       # → ~/.claude/skills/<name>/ に展開
```

これで全プロジェクトから `git-workflow` 等の skill が使える。プロジェクト固有の skill (例: `laravel-common`) は **プロジェクトの `apm.yml`** で declare、それ以外はグローバルへ、と使い分ける。

## skill 開発フロー (skill を作る側)

agent-skills repo を Skill Collection レイアウトで運用する場合:

### 新規 skill 追加

```sh
cd agent-skills/
mkdir -p skills/my-new-skill
cat > skills/my-new-skill/SKILL.md <<'EOF'
---
name: my-new-skill
description: What it does, when to invoke (1024字以内)
---

具体的な指示...
EOF

git checkout -b feature/add_my_new_skill
git add skills/my-new-skill/
git commit -m "feat: add my-new-skill"
git push -u origin feature/add_my_new_skill
gh pr create
```

merge 後、利用側で:
```sh
cd consumer-project/
# apm.yml に追加: - /path/to/agent-skills/skills/my-new-skill
apm install --update --target claude
```

### バージョン pin したい場合

`agent-skills/apm.yml` の `version:` を上げて tag を打つ:
```sh
git tag v0.2.0
git push origin v0.2.0
```

利用側:
```yaml
dependencies:
  apm:
    - owner/agent-skills#v0.2.0    # tag で pin
```

## よく使うコマンド早見

```sh
apm install                        # lockfile に従って install
apm install --update               # latest を取得して再 lockfile
apm install -g --target claude     # global install
apm install --skill <name>         # 特定 skill だけ
apm install --target all           # 対応エージェント全部に展開

apm list                           # 入っている依存
apm audit                          # ドリフト・脆弱性チェック
apm prune                          # apm.yml に無いやつを削除
apm pack                           # 配布物 (tar.gz / marketplace) 作成
apm init <name> --plugin           # 新規パッケージの scaffold
apm marketplace add <name>         # marketplace 追加
```

## ハマりどころ・Tips

- **skill の `name:` フィールドは親ディレクトリ名と一致必須**。違うと apm に弾かれる
- **install は copy 動作** (symlink ではない)。ソース更新を反映するには `apm install --update`
- **`-g` install のサポート差**: Claude / Gemini / Copilot CLI / Codex CLI は full、その他 (Cursor / Windsurf / OpenCode) は部分対応
- **`.claude/`, `.agents/`, `apm_modules/` は `.gitignore` 推奨**。manifest (`apm.yml` + `apm.lock.yaml`) だけ commit
- **複数エージェント運用**: `--target claude,codex` で両方に同時展開可能
- **shorthand SSH 切替え**: `apm install --ssh` (デフォルトは https)
- **alpha 段階のツール**: 0.x なので破壊的変更あり得る。重要環境では version 固定を推奨

## 関連リンク

- リポジトリ: https://github.com/microsoft/apm
- ドキュメント: https://microsoft.github.io/apm/
- Agent Skills 標準: https://agentskills.io/
- パッケージタイプ詳細: https://microsoft.github.io/apm/reference/package-types/
- マニフェストスキーマ: https://microsoft.github.io/apm/reference/manifest-schema/

---

**TL;DR**: SKILL.md フォーマットはそのままで、配布だけ npm 風に管理できる CLI。`apm.yml` に依存書いて `apm install --target claude` するだけで `.claude/skills/` に skill が展開される。
