#!/bin/bash
# skill-reflector pre-session hook for Claude Code
# Refreshes globally-installed skills before each session.
#
# 役割:
#   1. agent-skills repo を git pull (最新の skill 内容を取り込み)
#   2. apm install -g --update --target claude を実行し ~/.claude/skills/ を最新化
#      (agent-skills が Skill Collection、~/.apm/apm.yml で global 依存宣言済み前提)
#
# プロジェクト固有 skill (project の .claude/skills/) は別途
# `apm install --update` を手動 or /skill-manager sync で実行する。
#
# To register this hook, add to ~/.claude/settings.json:
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "matcher": "Task",
#         "command": "/path/to/skill-reflector/client/hooks/pre-session.sh"
#       }
#     ]
#   }
# }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
  exit 0
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ "${CLIENT_ENABLED:-false}" != "true" ]; then
  exit 0
fi

SKILLS_LOCAL_PATH="${SKILLS_LOCAL_PATH/#\~/$HOME}"

# 1. agent-skills repo を pull (失敗しても続行)
if [ -d "$SKILLS_LOCAL_PATH/.git" ]; then
  git -C "$SKILLS_LOCAL_PATH" pull --quiet 2>/dev/null || true
fi

# 2. global apm install を更新 (apm CLI と global apm.yml が両方ある時だけ)
APM_BIN="${APM_BIN:-$HOME/.local/bin/apm}"
if [ -x "$APM_BIN" ] && [ -f "$HOME/.apm/apm.yml" ]; then
  "$APM_BIN" install -g --update --target claude >/dev/null 2>&1 || true
fi
