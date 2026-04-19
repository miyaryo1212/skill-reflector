#!/bin/bash
# skill-reflector: Reflector cron entry point
#
# Runs the full analysis pipeline:
#   Layer 1: Import new logs into SQLite
#   Layer 2: Detect patterns and generate analysis input
#   Layer 3: Run headless Claude for skill improvement proposals
#   Apply proposals as GitHub Issues/PRs
#
# Setup:
#   crontab -e
#   0 3 * * * /path/to/skill-reflector/server/scripts/cron-reflector.sh >> ~/.skill-reflector/reflector.log 2>&1

set -euo pipefail

# cron runs with a minimal PATH; claude CLI lives under ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REFLECTOR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REFLECTOR_ROOT/.env"
REFLECTOR_LOG="${REFLECTOR_LOG:-$HOME/.skill-reflector/reflector.log}"
SLACK_WEBHOOK_FILE="${SLACK_WEBHOOK_FILE:-$HOME/.claude/slack-webhook}"

notify_failure() {
  local exit_code=$?
  local failed_line=${1:-unknown}
  if [ -r "$SLACK_WEBHOOK_FILE" ]; then
    local webhook host tail_log payload
    webhook=$(cat "$SLACK_WEBHOOK_FILE")
    host=$(hostname -s)
    tail_log=$(tail -n 15 "$REFLECTOR_LOG" 2>/dev/null || echo "(log unavailable)")
    payload=$(python3 -c '
import json, sys
text = ":rotating_light: *skill-reflector@{h} failed* (exit {c}, line {l})\n```\n{t}\n```".format(
    h=sys.argv[1], c=sys.argv[2], l=sys.argv[3], t=sys.argv[4])
print(json.dumps({"text": text}))
' "$host" "$exit_code" "$failed_line" "$tail_log")
    curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
      -d "$payload" "$webhook" >/dev/null 2>&1 || true
  fi
}
trap 'notify_failure $LINENO' ERR

if [ ! -f "$ENV_FILE" ]; then
  echo "$(date -Iseconds) ERROR: .env not found at $ENV_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ "${SERVER_ENABLED:-false}" != "true" ]; then
  exit 0
fi

LOG_SERVER_PATH="${LOG_SERVER_PATH/#\~/$HOME}"
DB_PATH="${DB_PATH/#\~/$HOME}"
SKILLS_LOCAL_PATH="${SKILLS_LOCAL_PATH/#\~/$HOME}"
REFLECTOR_MODEL="${REFLECTOR_MODEL:-claude-opus-4-6}"

echo "$(date -Iseconds) === Reflector run started ==="

# 1. Update skill-reflector itself
git -C "$REFLECTOR_ROOT" pull --quiet 2>/dev/null || true

# 2. Update agent-skills repo
if [ -d "$SKILLS_LOCAL_PATH/.git" ]; then
  git -C "$SKILLS_LOCAL_PATH" pull --quiet 2>/dev/null || true
fi

# 3. Layer 1: Import logs
echo "$(date -Iseconds) Layer 1: Importing logs..."
NEW_COUNT=$(python3 "$SCRIPT_DIR/import_logs.py" \
  --log-dir "$LOG_SERVER_PATH" \
  --db "$DB_PATH")

echo "$(date -Iseconds) Imported $NEW_COUNT new session(s)."

if [ "$NEW_COUNT" -eq 0 ]; then
  echo "$(date -Iseconds) No new logs. Skipping analysis."
  echo "$(date -Iseconds) === Reflector run finished (skipped) ==="
  exit 0
fi

# 4. Layer 2: Pattern detection → analysis input
echo "$(date -Iseconds) Layer 2: Detecting patterns..."
ANALYSIS_INPUT=$(mktemp /tmp/reflector-input-XXXXXX.json)
python3 "$SCRIPT_DIR/detect_patterns.py" \
  --db "$DB_PATH" \
  --skills-dir "$SKILLS_LOCAL_PATH" \
  --output "$ANALYSIS_INPUT"

# 5. Layer 3: Headless Claude analysis
echo "$(date -Iseconds) Layer 3: Running Claude analysis (model: $REFLECTOR_MODEL)..."
PROPOSALS=$(claude -p \
  --model "$REFLECTOR_MODEL" \
  --system-prompt "$(cat "$REFLECTOR_ROOT/server/reflector/analyze.md")" \
  < "$ANALYSIS_INPUT")

# 6. Apply proposals to GitHub
echo "$(date -Iseconds) Applying proposals..."
echo "$PROPOSALS" | python3 "$SCRIPT_DIR/apply_proposals.py" \
  --repo "$SKILLS_REPO" \
  --auto-reflection "${AUTO_REFLECTION:-false}"

# Cleanup
rm -f "$ANALYSIS_INPUT"

echo "$(date -Iseconds) === Reflector run finished ==="
