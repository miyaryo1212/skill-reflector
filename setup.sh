#!/bin/bash
# skill-reflector setup script (apm-aligned).
#
# 役割:
#   1. agent-skills repo を clone (なければ) / pull
#   2. ~/.apm/apm.yml を初期セットアップ (cross-cutting global skills を宣言)
#   3. apm install -g --target claude で ~/.claude/skills/ にデプロイ
#   4. skill-manager skill 自体を ~/.claude/skills/ (および ~/.codex/skills/) に symlink
#   5. (任意) Reflector サーバー側ディレクトリ準備
#
# 前提: ~/.local/bin/apm が install 済み
#   curl -sSL https://github.com/microsoft/apm/releases/latest/download/apm-linux-x86_64.tar.gz | \
#     tar -xz -C /tmp && cp /tmp/apm-linux-x86_64/apm ~/.local/bin/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "=== skill-reflector setup (apm) ==="

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env not found. Copy .env.sample to .env and configure it first."
  echo "  cp .env.sample .env"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

SKILLS_LOCAL_PATH="${SKILLS_LOCAL_PATH/#\~/$HOME}"
DB_PATH="${DB_PATH/#\~/$HOME}"
LOG_SERVER_PATH="${LOG_SERVER_PATH/#\~/$HOME}"
APM_BIN="${APM_BIN:-$HOME/.local/bin/apm}"

# --- 1. agent-skills repo の clone/pull ---
echo ""
echo "--- agent-skills repo ---"
if [ -d "$SKILLS_LOCAL_PATH/.git" ]; then
  echo "Pulling latest at $SKILLS_LOCAL_PATH..."
  git -C "$SKILLS_LOCAL_PATH" pull --quiet
else
  echo "Cloning agent-skills repo to $SKILLS_LOCAL_PATH..."
  mkdir -p "$(dirname "$SKILLS_LOCAL_PATH")"
  git clone "$SKILLS_REPO" "$SKILLS_LOCAL_PATH"
fi

# --- 2 & 3. apm でグローバル skill をデプロイ ---
if [ -x "$APM_BIN" ]; then
  echo ""
  echo "--- Global skills via apm ---"
  if [ ! -f "$HOME/.apm/apm.yml" ]; then
    mkdir -p "$HOME/.apm"
    cat > "$HOME/.apm/apm.yml" <<YAML
name: ${USER:-user}
version: 1.0.0
description: Personal global agent skills (cross-cutting)
dependencies:
  apm:
    # cross-cutting skills のみ。プロジェクト固有 skill は各プロジェクトの apm.yml で管理
    - $SKILLS_LOCAL_PATH/skills/ai-dev-estimation
    - $SKILLS_LOCAL_PATH/skills/docs-conventions
    - $SKILLS_LOCAL_PATH/skills/git-workflow
    - $SKILLS_LOCAL_PATH/skills/preview-server
    - $SKILLS_LOCAL_PATH/skills/project-conventions
    - $SKILLS_LOCAL_PATH/skills/review
    - $SKILLS_LOCAL_PATH/skills/secure-credential
    - $SKILLS_LOCAL_PATH/skills/ssh-hosts
    - $SKILLS_LOCAL_PATH/skills/user-context
  mcp: []
YAML
    echo "Created ~/.apm/apm.yml"
  else
    echo "~/.apm/apm.yml already exists, leaving as is"
  fi
  "$APM_BIN" install -g --target claude
else
  echo ""
  echo "Warning: apm CLI not found at $APM_BIN. Skipping global skill deploy."
  echo "  Install apm and re-run setup.sh."
fi

# --- 4. skill-manager skill を symlink ---
echo ""
echo "--- skill-manager symlink ---"
SKILL_MANAGER_SRC="$SCRIPT_DIR/client/skills/skill-manager"

if [ -d "$HOME/.claude" ]; then
  CLAUDE_SKILL_MANAGER="$HOME/.claude/skills/skill-manager"
  mkdir -p "$HOME/.claude/skills"
  if [ -L "$CLAUDE_SKILL_MANAGER" ] || [ -e "$CLAUDE_SKILL_MANAGER" ]; then
    rm -rf "$CLAUDE_SKILL_MANAGER"
  fi
  ln -s "$SKILL_MANAGER_SRC" "$CLAUDE_SKILL_MANAGER"
  echo "  Claude Code: $CLAUDE_SKILL_MANAGER -> $SKILL_MANAGER_SRC"
fi

if [ -d "$HOME/.codex" ]; then
  CODEX_SKILL_MANAGER="$HOME/.codex/skills/skill-manager"
  mkdir -p "$HOME/.codex/skills"
  if [ -L "$CODEX_SKILL_MANAGER" ] || [ -e "$CODEX_SKILL_MANAGER" ]; then
    rm -rf "$CODEX_SKILL_MANAGER"
  fi
  ln -s "$SKILL_MANAGER_SRC" "$CODEX_SKILL_MANAGER"
  echo "  Codex: $CODEX_SKILL_MANAGER -> $SKILL_MANAGER_SRC"
fi

# --- 5. Reflector サーバー (有効時のみ) ---
if [ "${SERVER_ENABLED:-false}" = "true" ]; then
  echo ""
  echo "--- Reflector server setup ---"
  mkdir -p "$(dirname "$DB_PATH")"
  echo "  Log DB path: $DB_PATH"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  - 各プロジェクトに apm.yml を置いて 'apm install --target claude' で skill 配備"
echo "  - 既存プロジェクトは /skill-manager sync で内部的に apm install を呼べる"
