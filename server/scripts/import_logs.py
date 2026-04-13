#!/usr/bin/env python3
"""Layer 1: Import session logs (JSONL) into SQLite.

Scans log directories for unprocessed JSONL files, extracts session metadata,
skill/tool usage, and user intents, then stores them in SQLite.
Moves processed files to a processed/ subdirectory.

Usage:
    python3 import_logs.py --log-dir ~/.skill-reflector/logs --db ~/.skill-reflector/logs.db

Prints the number of newly imported sessions to stdout (for cron-reflector.sh).
"""

import argparse
import json
import os
import shutil
import sqlite3
import sys
from collections import Counter
from pathlib import Path

INTENT_MAX_LENGTH = 300


def init_db(db_path: str) -> sqlite3.Connection:
    schema_path = Path(__file__).resolve().parent.parent / "sql" / "schema.sql"
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    with open(schema_path) as f:
        conn.executescript(f.read())
    return conn


def parse_session(filepath: Path) -> dict | None:
    """Parse a JSONL session log and extract structured metadata."""
    entries = []
    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except (OSError, UnicodeDecodeError):
        return None

    if not entries:
        return None

    # Extract session ID from entries
    session_id = None
    for e in entries:
        sid = e.get("sessionId")
        if sid:
            session_id = sid
            break
    if not session_id:
        return None

    # Session metadata (from first assistant/user entry with metadata)
    project = None
    entrypoint = None
    git_branch = None
    for e in entries:
        if e.get("type") in ("assistant", "user"):
            project = project or e.get("cwd")
            entrypoint = entrypoint or e.get("entrypoint")
            git_branch = git_branch or e.get("gitBranch")
            if project and entrypoint:
                break

    # Title from ai-title entry
    title = None
    for e in entries:
        if e.get("type") == "ai-title":
            msg = e.get("message", {})
            if isinstance(msg, dict):
                for c in msg.get("content", []):
                    if isinstance(c, dict) and c.get("type") == "text":
                        title = c.get("text", "")[:200]
                        break
                if not title:
                    title = msg.get("title", "")[:200] or None
            break

    # Timestamps
    timestamps = [e.get("timestamp") for e in entries if e.get("timestamp")]
    started_at = min(timestamps) if timestamps else None
    ended_at = max(timestamps) if timestamps else None

    # Count user turns and extract intents
    user_intents = []
    turn_index = 0
    for e in entries:
        if e.get("type") != "user":
            continue
        turn_index += 1
        msg = e.get("message", {})
        if not isinstance(msg, dict):
            continue
        for c in msg.get("content", []):
            if isinstance(c, dict) and c.get("type") == "text":
                text = c.get("text", "").strip()
                # Skip IDE-generated messages (file opened notifications, etc.)
                if text.startswith("<ide_") or text.startswith("<system"):
                    continue
                if text:
                    user_intents.append({
                        "turn_index": turn_index,
                        "intent_text": text[:INTENT_MAX_LENGTH],
                        "timestamp": e.get("timestamp"),
                    })
                break

    turn_count = turn_index

    # Extract skill and tool usage from assistant messages
    skill_counts: Counter = Counter()
    tool_counts: Counter = Counter()
    for e in entries:
        if e.get("type") != "assistant":
            continue
        msg = e.get("message", {})
        if not isinstance(msg, dict):
            continue
        for c in msg.get("content", []):
            if not isinstance(c, dict) or c.get("type") != "tool_use":
                continue
            tool_name = c.get("name", "")
            if tool_name:
                tool_counts[tool_name] += 1
            if tool_name == "Skill":
                skill_name = c.get("input", {}).get("skill", "")
                if skill_name:
                    skill_counts[skill_name] += 1

    return {
        "id": session_id,
        "project": project,
        "entrypoint": entrypoint,
        "git_branch": git_branch,
        "title": title,
        "started_at": started_at,
        "ended_at": ended_at,
        "turn_count": turn_count,
        "user_intents": user_intents,
        "skill_counts": dict(skill_counts),
        "tool_counts": dict(tool_counts),
    }


def import_file(conn: sqlite3.Connection, filepath: Path, machine: str) -> bool:
    """Import a single JSONL file. Returns True if successfully imported."""
    session = parse_session(filepath)
    if not session:
        return False

    # Skip if already imported
    row = conn.execute(
        "SELECT 1 FROM sessions WHERE id = ?", (session["id"],)
    ).fetchone()
    if row:
        return False

    conn.execute(
        """INSERT INTO sessions (id, machine, project, entrypoint, git_branch,
           title, started_at, ended_at, turn_count, source_file)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            session["id"],
            machine,
            session["project"],
            session["entrypoint"],
            session["git_branch"],
            session["title"],
            session["started_at"],
            session["ended_at"],
            session["turn_count"],
            str(filepath),
        ),
    )

    for skill_name, count in session["skill_counts"].items():
        conn.execute(
            """INSERT INTO skill_usages (session_id, skill_name, invocation_count)
               VALUES (?, ?, ?)""",
            (session["id"], skill_name, count),
        )

    for tool_name, count in session["tool_counts"].items():
        conn.execute(
            """INSERT INTO tool_usages (session_id, tool_name, use_count)
               VALUES (?, ?, ?)""",
            (session["id"], tool_name, count),
        )

    for intent in session["user_intents"]:
        conn.execute(
            """INSERT INTO user_intents (session_id, turn_index, intent_text, timestamp)
               VALUES (?, ?, ?, ?)""",
            (
                session["id"],
                intent["turn_index"],
                intent["intent_text"],
                intent["timestamp"],
            ),
        )

    return True


def main():
    parser = argparse.ArgumentParser(description="Import session logs into SQLite")
    parser.add_argument("--log-dir", required=True, help="Root log directory")
    parser.add_argument("--db", required=True, help="SQLite database path")
    args = parser.parse_args()

    log_dir = Path(args.log_dir).expanduser()
    db_path = Path(args.db).expanduser()
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = init_db(str(db_path))
    imported_count = 0

    # Scan each machine subdirectory
    if not log_dir.is_dir():
        print("0")
        return

    for machine_dir in sorted(log_dir.iterdir()):
        if not machine_dir.is_dir() or machine_dir.name == "processed":
            continue

        machine = machine_dir.name
        processed_dir = machine_dir / "processed"

        jsonl_files = sorted(machine_dir.glob("*.jsonl"))
        if not jsonl_files:
            continue

        for filepath in jsonl_files:
            try:
                if import_file(conn, filepath, machine):
                    imported_count += 1
                # Move to processed regardless (avoid reprocessing broken files)
                processed_dir.mkdir(exist_ok=True)
                shutil.move(str(filepath), str(processed_dir / filepath.name))
            except Exception as e:
                print(f"Error processing {filepath}: {e}", file=sys.stderr)
                continue

    conn.commit()
    conn.close()
    print(imported_count)


if __name__ == "__main__":
    main()
