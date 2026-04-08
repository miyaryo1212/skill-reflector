#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "=== skill-reflector setup ==="

# .env の存在確認
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env not found. Copy .env.sample to .env and configure it first."
  echo "  cp .env.sample .env"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# SKILLS_LOCAL_PATH を展開
SKILLS_LOCAL_PATH="${SKILLS_LOCAL_PATH/#\~/$HOME}"
DB_PATH="${DB_PATH/#\~/$HOME}"
LOG_SERVER_PATH="${LOG_SERVER_PATH/#\~/$HOME}"

# --- agent-skills repo の clone/pull ---
echo ""
echo "--- agent-skills repo ---"
if [ -d "$SKILLS_LOCAL_PATH/.git" ]; then
  echo "agent-skills repo already exists at $SKILLS_LOCAL_PATH, pulling..."
  git -C "$SKILLS_LOCAL_PATH" pull --quiet
else
  echo "Cloning agent-skills repo to $SKILLS_LOCAL_PATH..."
  mkdir -p "$(dirname "$SKILLS_LOCAL_PATH")"
  git clone "$SKILLS_REPO" "$SKILLS_LOCAL_PATH"
fi

# --- skill-manager をグローバル skill として登録 ---
echo ""
echo "--- Registering skill-manager as global skill ---"

SKILL_MANAGER_SRC="$SCRIPT_DIR/client/skills/skill-manager"

# Claude Code
CLAUDE_SKILLS_DIR="$HOME/.claude/skills/skill-manager"
if [ -d "$HOME/.claude" ]; then
  if [ -L "$CLAUDE_SKILLS_DIR" ]; then
    rm "$CLAUDE_SKILLS_DIR"
  fi
  mkdir -p "$HOME/.claude/skills"
  ln -s "$SKILL_MANAGER_SRC" "$CLAUDE_SKILLS_DIR"
  echo "Registered for Claude Code: $CLAUDE_SKILLS_DIR -> $SKILL_MANAGER_SRC"
fi

# Codex
CODEX_SKILLS_DIR="$HOME/.codex/skills/skill-manager"
if [ -d "$HOME/.codex" ]; then
  if [ -L "$CODEX_SKILLS_DIR" ]; then
    rm "$CODEX_SKILLS_DIR"
  fi
  mkdir -p "$HOME/.codex/skills"
  ln -s "$SKILL_MANAGER_SRC" "$CODEX_SKILLS_DIR"
  echo "Registered for Codex: $CODEX_SKILLS_DIR -> $SKILL_MANAGER_SRC"
fi

# --- Server setup (if enabled) ---
if [ "${SERVER_ENABLED:-false}" = "true" ]; then
  echo ""
  echo "--- Server setup ---"
  mkdir -p "$(dirname "$DB_PATH")"
  echo "Log DB path: $DB_PATH"
  echo "Server setup complete."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Run '/skill-manager sync' in your project to sync skills"
echo "  2. Add .skill-reflector.yaml to your project to declare namespaces"
