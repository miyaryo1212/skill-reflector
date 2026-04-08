#!/bin/bash
# skill-reflector post-session hook for Claude Code
# Records and sends session logs automatically at session end
#
# To register this hook, add to ~/.claude/settings.json:
# {
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Task",
#         "command": "/path/to/skill-reflector/client/hooks/post-session.sh"
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

MACHINE_NAME="${MACHINE_NAME:-$(hostname)}"
LOG_SERVER_PATH="${LOG_SERVER_PATH/#\~/$HOME}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILENAME="${MACHINE_NAME}_${TIMESTAMP}.jsonl"

# Find the most recent session log
# Claude Code: ~/.claude/projects/<project>/*.jsonl
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
if [ -d "$CLAUDE_PROJECTS_DIR" ]; then
  LATEST_LOG=$(find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi

if [ -z "${LATEST_LOG:-}" ]; then
  exit 0
fi

# Send/store based on mode
if [ "${SERVER_ENABLED:-false}" = "true" ]; then
  # Local mode: copy to local log directory
  LOCAL_LOG_DIR="$LOG_SERVER_PATH/$MACHINE_NAME"
  mkdir -p "$LOCAL_LOG_DIR"
  cp "$LATEST_LOG" "$LOCAL_LOG_DIR/$LOG_FILENAME"
else
  # Remote mode: scp to server
  if [ -n "${LOG_SERVER:-}" ]; then
    scp -q "$LATEST_LOG" "$LOG_SERVER:$LOG_SERVER_PATH/$MACHINE_NAME/$LOG_FILENAME" 2>/dev/null || true
  fi
fi
