#!/bin/bash
# skill-reflector post-session hook for Claude Code
# Records and sends session logs automatically at session end
#
# To register this hook, add to ~/.claude/settings.json:
# {
#   "hooks": {
#     "Stop": [
#       {
#         "matcher": "",
#         "hooks": [
#           { "type": "command", "command": "/path/to/skill-reflector/client/hooks/post-session.sh" }
#         ]
#       }
#     ]
#   }
# }
#
# Claude Code passes hook input JSON on stdin (session_id, transcript_path, ...).
# We ship the stopping session's own transcript; the mtime-based fallback only
# covers callers that provide no stdin payload (e.g. manual invocation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
SHIP_LOG="$HOME/.skill-reflector/ship.log"

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

ship_log() {
  mkdir -p "$(dirname "$SHIP_LOG")"
  echo "$(date -Is) $*" >> "$SHIP_LOG"
}

# Prefer the stopping session's own transcript from hook input (stdin JSON)
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

SESSION_LOG=""
SESSION_ID=""
if [ -n "$HOOK_INPUT" ] && command -v jq >/dev/null 2>&1; then
  SESSION_LOG="$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  SESSION_ID="$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

if [ -n "$SESSION_LOG" ] && [ ! -f "$SESSION_LOG" ]; then
  ship_log "WARN transcript_path not found: $SESSION_LOG (falling back to mtime scan)"
  SESSION_LOG=""
fi

# Fallback: most recent session log under ~/.claude/projects
# (imprecise: with concurrent sessions this may pick another session's file)
if [ -z "$SESSION_LOG" ]; then
  CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
  if [ -d "$CLAUDE_PROJECTS_DIR" ]; then
    SESSION_LOG=$(find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  fi
fi

if [ -z "${SESSION_LOG:-}" ]; then
  exit 0
fi

# Stable name per session: re-ships of the same session overwrite instead of
# piling up timestamped duplicates. The server re-imports fuller versions.
if [ -n "$SESSION_ID" ]; then
  LOG_FILENAME="${MACHINE_NAME}_${SESSION_ID}.jsonl"
else
  LOG_FILENAME="${MACHINE_NAME}_${TIMESTAMP}.jsonl"
fi

# Send/store based on mode
if [ "${SERVER_ENABLED:-false}" = "true" ]; then
  # Local mode: copy to local log directory
  LOCAL_LOG_DIR="$LOG_SERVER_PATH/$MACHINE_NAME"
  mkdir -p "$LOCAL_LOG_DIR"
  if cp "$SESSION_LOG" "$LOCAL_LOG_DIR/$LOG_FILENAME"; then
    ship_log "OK local $LOG_FILENAME <- $SESSION_LOG"
  else
    ship_log "FAIL local cp $LOG_FILENAME <- $SESSION_LOG"
  fi
else
  # Remote mode: scp to server (failures must not break the Stop hook,
  # but they must be visible somewhere -> ship.log)
  if [ -n "${LOG_SERVER:-}" ]; then
    if scp -q -o ConnectTimeout=10 "$SESSION_LOG" "$LOG_SERVER:$LOG_SERVER_PATH/$MACHINE_NAME/$LOG_FILENAME" 2>>"$SHIP_LOG"; then
      ship_log "OK $LOG_SERVER $LOG_FILENAME <- $SESSION_LOG"
    else
      ship_log "FAIL scp $LOG_SERVER $LOG_FILENAME <- $SESSION_LOG"
    fi
  fi
fi

exit 0
