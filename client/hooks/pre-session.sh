#!/bin/bash
# skill-reflector pre-session hook for Claude Code
# Runs /skill-manager sync automatically at session start
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

# Pull latest skills (fail silently)
if [ -d "$SKILLS_LOCAL_PATH/.git" ]; then
  git -C "$SKILLS_LOCAL_PATH" pull --quiet 2>/dev/null || true
fi
