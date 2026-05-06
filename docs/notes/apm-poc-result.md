# apm 移行 PoC 結果 (Phase 0)

実施日: 2026-05-07
apm version: **v0.12.2**
判定: **Go** (5/5 通過、移行コスト見積を 3日±1日 → **2日** に下方修正)

## サンドボックス構成

```
~/tmp/apm-poc/
├── sandbox-skills/        # agent-skills を Skill Collection 形式で複製
│   ├── apm.yml           # name + version のみ
│   └── skills/<name>/SKILL.md   (14 skill, namespaces は <ns>-<name> 形式に flat 化)
├── consumer-claude/      # apm install --target claude
├── consumer-codex/       # apm install --target codex
├── consumer-cross/       # apm install --target agent-skills
├── consumer-selective/   # 個別 skill のみ依存
├── consumer-multi/       # claude+codex 同時
└── fakehome/             # HOME 切替えクリーン環境テスト
```

## Go/No-Go 5項目

| # | 確認項目 | 結果 | 詳細 |
|---|---|---|---|
| 1 | Claude Code が installed skill を認識する | ✅ | `apm install --target claude` 実行直後に Claude Code 側の system-reminder に新 skill が出現（実機確認） |
| 2 | Codex が installed skill を認識する | ✅ | `--target codex` で `.agents/skills/` に展開（Codex spec 準拠パス）。CLI 実起動未検証 |
| 3 | local path 依存が解決される | ✅ | `../sandbox-skills` および `../sandbox-skills/skills/<name>` 両方 install 成功 |
| 4 | global install の現実解がある | ✅ | `apm install -g --target claude` で `~/.claude/skills/` に展開。**既存 symlink はマージ保護**（破壊しない） |
| 5 | namespaces を表現できる | ✅ | flat 化 (`<ns>-<name>`) で命名衝突回避、`--skill NAME` か path 指定で selective install 可能 |

## 主要発見

### A. install の挙動

```sh
apm install --target claude         # → .claude/skills/<name>/SKILL.md  (project-local)
apm install --target codex          # → .agents/skills/<name>/SKILL.md  (project-local, cross-client conv.)
apm install --target agent-skills   # → .agents/skills/  (codex と同じ場所)
apm install --target claude,codex   # → 両方同時展開
apm install -g --target claude      # → ~/.claude/skills/  (user-scope)
```

- **ファイルは copy 配置**（symlink ではない）。Reflector が PR 出すときの「source of truth」は agent-skills repo のままで OK
- `apm.lock.yaml` が自動生成、commit SHA で再現性確保
- `apm_modules/` が自動で `.gitignore` に追記される

### B. Global install と既存 symlink の共存

`~/.claude/skills/` に既存 symlink が 9本ある状態で `apm install -g --target claude` を実行 →
- 既存 symlink は **保持** (上書きされない)
- 新規 skill のみ実ディレクトリとして追加
- 衝突時は `--force` で上書き可能

→ 段階移行が可能。「symlink → apm 管理」への切替は 1 skill ずつ進められる。

### C. namespaces 戦略の確定

Phase 1 では **flat 化** で行く:
- `namespaces/agent-sentinel/add-target/` → `skills/agent-sentinel-add-target/`
- SKILL.md の `name:` フィールドもディレクトリ名に合わせて変更

理由:
- apm の `--skill NAME` フラグおよび path 指定の selective install で namespaces 相当の選択は実現可能
- subpackage 化は overkill（apm.yml 別建てが必要になる）

ただし既存 SKILL.md 2本（add-target, update-history）は **name 変更が必要**:
| 旧 path | 新 path | name 変更 |
|---|---|---|
| namespaces/agent-sentinel/add-target/SKILL.md | skills/agent-sentinel-add-target/SKILL.md | `add-target` → `agent-sentinel-add-target` |
| namespaces/trend-research/update-history/SKILL.md | skills/trend-research-update-history/SKILL.md | `update-history` → `trend-research-update-history` |

他 3 本（laravel-common / python-common / design-dashboard）は既に prefix 済みなので変更不要。

### D. 想定外だったポイント

- **`apm install --plugin` flag は init で使う、install 時は無関係**
- **install 経路が SKILL_BUNDLE / SKILL_COLLECTION / PLUGIN_COLLECTION で自動分岐**（lockfile に `package_type` が記録される）
- **`apm pack` は依存元 (consumer 側) ではなく配布物作成用**。skill collection repo 側で叩いても "Nothing to pack" になる
- **apm CLI は user-scope install を sudo 要求する**。`/usr/local/bin` 以外の `~/.local/bin` でも sudo 呼ぶバグ気味挙動 → tarball 直展開で回避可能

### E. 想定通りでスキップした検証

- transitive dependencies（agent-skills repo は依存を持たないので不要）
- marketplace 機能（自前 marketplace は当面不要）
- MCP server install（skill 配布とは別レイヤ、必要時に検証）

## 移行コスト再見積もり

元見積もり: **3日 ± 1日**

リスク 3つが全部解消されたので下方修正:
- ✅ global install 動作 → 想定 +0.5〜1日 を回避
- ✅ codex target 展開先 spec 通り → 想定 +2-3h を回避
- ✅ namespaces flat 化で確定 → 想定 +2-3h を回避

**新見積もり: 2日**

| Phase | 工数 |
|---|---|
| 1. agent-skills repo restructure | 2-3h |
| 2. consumer 3プロジェクト移行 | 2-3h |
| 3. skill-manager / hooks 縮小 | 0.5-1日 |
| 4. Reflector 出力先調整 | 2-3h |
| 5. cleanup | 2-3h |

## クリーンアップ済み

- 実 `~/.claude/skills/` に install されたテスト 6 dir → 削除済み（symlink は保持）
- `~/.apm/apm.yml`, `~/.apm/apm.lock.yaml`, `~/.apm/apm_modules/` → 削除済み
- `~/tmp/apm-poc/` は **温存**（Phase 1 移行作業時の参考用）

## 次のアクション

Phase 1 (agent-skills repo restructure) に進む。手順:
1. agent-skills repo に feature branch を切る
2. `global/` → `skills/` rename + namespaces flat 化
3. add-target / update-history の SKILL.md `name:` 修正
4. `apm.yml` をルートに追加
5. PoC の consumer-claude を流用して install 確認
6. PR → main マージ
