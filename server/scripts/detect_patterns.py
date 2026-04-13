#!/usr/bin/env python3
"""Layer 2: Detect patterns from imported session data and generate analysis input JSON.

Runs SQL queries against the SQLite database to identify:
  A. New skill candidates (skillless sessions with repeating intents)
  B. Skill improvement candidates (high turn count after skill use)
  C. Skill usage statistics
  D. Unused skills (in agent-skills repo but not used in 30 days)
  E. Tool usage trends in skillless sessions

Combines patterns with current skill definitions into a single JSON file
for Layer 3 (headless Claude) to analyze.

Usage:
    python3 detect_patterns.py --db ~/.skill-reflector/logs.db \
        --skills-dir ~/.skill-reflector/agent-skills --output /tmp/analysis.json
"""

import argparse
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

ANALYSIS_WINDOW_DAYS = 30
SAMPLE_LIMIT = 50


def load_skills(skills_dir: Path) -> dict:
    """Load current skill definitions from the agent-skills repo."""
    result = {"global": [], "namespaces": {}}

    global_dir = skills_dir / "global"
    if global_dir.is_dir():
        for skill_dir in sorted(global_dir.iterdir()):
            skill_file = skill_dir / "SKILL.md" if skill_dir.is_dir() else None
            if skill_file and skill_file.exists():
                result["global"].append({
                    "name": skill_dir.name,
                    "content": skill_file.read_text(errors="replace"),
                })
            elif skill_dir.is_file() and skill_dir.suffix == ".md":
                result["global"].append({
                    "name": skill_dir.stem,
                    "content": skill_dir.read_text(errors="replace"),
                })

    ns_dir = skills_dir / "namespaces"
    if ns_dir.is_dir():
        for ns in sorted(ns_dir.iterdir()):
            if not ns.is_dir():
                continue
            ns_skills = []
            for skill_path in sorted(ns.rglob("SKILL.md")):
                rel = skill_path.parent.relative_to(ns)
                name = ".".join(rel.parts) if rel.parts else skill_path.parent.name
                ns_skills.append({
                    "name": name,
                    "content": skill_path.read_text(errors="replace"),
                })
            if ns_skills:
                result["namespaces"][ns.name] = ns_skills

    return result


def get_all_skill_names(skills: dict) -> set:
    """Extract all skill names from the loaded skills structure."""
    names = set()
    for s in skills["global"]:
        names.add(s["name"])
    for ns, ns_skills in skills["namespaces"].items():
        for s in ns_skills:
            names.add(f"{ns}.{s['name']}" if s["name"] != ns else s["name"])
            names.add(s["name"])
    return names


def detect_new_skill_candidates(conn: sqlite3.Connection, cutoff: str) -> list:
    """A: Skillless sessions grouped by project with all intents.

    Instead of exact-match grouping (which rarely finds duplicates),
    collect all intents from skillless sessions per project and let
    Layer 3 (Claude) identify similar patterns across them.
    """
    # Get projects with skillless sessions, grouped by directory name
    # (normalizes across machines: /home/user/project/foo and /home/user/deploy/foo → foo)
    project_rows = conn.execute("""
        SELECT replace(s.project, rtrim(s.project, replace(s.project, '/', '')), '') as project_name,
               COUNT(DISTINCT s.id) as session_count
        FROM sessions s
        LEFT JOIN skill_usages su ON s.id = su.session_id
        WHERE su.session_id IS NULL
          AND s.started_at > ?
          AND s.turn_count > 3
          AND s.project IS NOT NULL
        GROUP BY project_name
        HAVING session_count >= 2
        ORDER BY session_count DESC
        LIMIT 20
    """, (cutoff,)).fetchall()

    results = []
    for project_name, session_count in project_rows:
        # Collect intents and tool profiles, matching by directory name suffix
        intent_rows = conn.execute("""
            SELECT ui.intent_text, s.turn_count, s.id
            FROM user_intents ui
            JOIN sessions s ON ui.session_id = s.id
            LEFT JOIN skill_usages su ON s.id = su.session_id
            WHERE su.session_id IS NULL
              AND s.project LIKE '%/' || ?
              AND s.started_at > ?
              AND s.turn_count > 3
              AND ui.turn_index <= 3
              AND ui.intent_text IS NOT NULL
              AND length(trim(ui.intent_text)) > 10
            ORDER BY s.started_at DESC
        """, (project_name, cutoff)).fetchall()

        # Collect tool usage profile for these sessions
        tool_rows = conn.execute("""
            SELECT tu.tool_name, SUM(tu.use_count) as total
            FROM tool_usages tu
            JOIN sessions s ON tu.session_id = s.id
            LEFT JOIN skill_usages su ON s.id = su.session_id
            WHERE su.session_id IS NULL
              AND s.project LIKE '%/' || ?
              AND s.started_at > ?
              AND s.turn_count > 3
            GROUP BY tu.tool_name
            ORDER BY total DESC
            LIMIT 10
        """, (project_name, cutoff)).fetchall()

        if not intent_rows:
            continue

        # Deduplicate intents per session (take first 3 turns per session)
        seen_sessions = {}
        intents = []
        for text, turn_count, sid in intent_rows:
            if sid not in seen_sessions:
                seen_sessions[sid] = 0
            seen_sessions[sid] += 1
            if seen_sessions[sid] <= 3:
                intents.append({"text": text, "turn_count": turn_count})

        results.append({
            "project": project_name,
            "session_count": session_count,
            "intents": intents[:30],  # Cap to avoid bloat
            "top_tools": {r[0]: r[1] for r in tool_rows},
        })

    return results


def detect_improvement_candidates(conn: sqlite3.Connection, cutoff: str) -> list:
    """B: Skills with high average turn count (potential correction signals)."""
    rows = conn.execute("""
        SELECT su.skill_name,
               ROUND(AVG(s.turn_count), 1) as avg_turns,
               COUNT(*) as usage_count,
               MAX(s.turn_count) as max_turns
        FROM skill_usages su
        JOIN sessions s ON su.session_id = s.id
        WHERE s.started_at > ?
        GROUP BY su.skill_name
        ORDER BY avg_turns DESC
    """, (cutoff,)).fetchall()
    return [
        {
            "skill_name": r[0],
            "avg_turns": r[1],
            "usage_count": r[2],
            "max_turns": r[3],
        }
        for r in rows
    ]


def detect_usage_stats(conn: sqlite3.Connection, cutoff: str) -> list:
    """C: Skill usage frequency ranking."""
    rows = conn.execute("""
        SELECT skill_name,
               SUM(invocation_count) as total_invocations,
               COUNT(DISTINCT session_id) as session_count
        FROM skill_usages
        WHERE session_id IN (SELECT id FROM sessions WHERE started_at > ?)
        GROUP BY skill_name
        ORDER BY total_invocations DESC
    """, (cutoff,)).fetchall()
    return [
        {
            "skill_name": r[0],
            "total_invocations": r[1],
            "session_count": r[2],
        }
        for r in rows
    ]


def detect_unused_skills(
    conn: sqlite3.Connection, cutoff: str, all_skill_names: set
) -> list:
    """D: Skills in repo but not used in the analysis window."""
    rows = conn.execute("""
        SELECT DISTINCT skill_name
        FROM skill_usages
        WHERE session_id IN (SELECT id FROM sessions WHERE started_at > ?)
    """, (cutoff,)).fetchall()
    used = {r[0] for r in rows}
    unused = sorted(all_skill_names - used)
    return [{"skill_name": name} for name in unused]


def detect_tool_trends(conn: sqlite3.Connection, cutoff: str) -> list:
    """E: Tool usage trends in skillless sessions."""
    rows = conn.execute("""
        SELECT s.project, tu.tool_name, SUM(tu.use_count) as total
        FROM tool_usages tu
        JOIN sessions s ON tu.session_id = s.id
        LEFT JOIN skill_usages su ON s.id = su.session_id
        WHERE su.session_id IS NULL
          AND s.started_at > ?
        GROUP BY s.project, tu.tool_name
        ORDER BY total DESC
        LIMIT ?
    """, (cutoff, SAMPLE_LIMIT)).fetchall()
    return [
        {"project": r[0], "tool_name": r[1], "total_uses": r[2]}
        for r in rows
    ]


def get_recent_intents_sample(conn: sqlite3.Connection, cutoff: str) -> list:
    """Get a sample of recent sessions with their intents and usage."""
    rows = conn.execute("""
        SELECT s.id, s.project, s.turn_count, s.title
        FROM sessions s
        WHERE s.started_at > ?
        ORDER BY s.started_at DESC
        LIMIT ?
    """, (cutoff, SAMPLE_LIMIT)).fetchall()

    samples = []
    for r in rows:
        session_id = r[0]

        # First intent
        intent_row = conn.execute("""
            SELECT intent_text FROM user_intents
            WHERE session_id = ? AND turn_index = 1
        """, (session_id,)).fetchone()

        # Skills used
        skill_rows = conn.execute("""
            SELECT skill_name FROM skill_usages WHERE session_id = ?
        """, (session_id,)).fetchall()

        # Tool usage
        tool_rows = conn.execute("""
            SELECT tool_name, use_count FROM tool_usages WHERE session_id = ?
        """, (session_id,)).fetchall()

        samples.append({
            "session_id": session_id,
            "project": r[1],
            "turn_count": r[2],
            "title": r[3],
            "intent": intent_row[0] if intent_row else None,
            "skills_used": [sr[0] for sr in skill_rows],
            "tools_used": {tr[0]: tr[1] for tr in tool_rows},
        })

    return samples


def get_session_summary(conn: sqlite3.Connection, cutoff: str) -> dict:
    """Get overall session statistics."""
    row = conn.execute("""
        SELECT COUNT(*), COUNT(DISTINCT project), COUNT(DISTINCT machine)
        FROM sessions WHERE started_at > ?
    """, (cutoff,)).fetchone()
    return {
        "total_sessions": row[0],
        "unique_projects": row[1],
        "unique_machines": row[2],
    }


def main():
    parser = argparse.ArgumentParser(description="Detect patterns and generate analysis input")
    parser.add_argument("--db", required=True, help="SQLite database path")
    parser.add_argument("--skills-dir", required=True, help="agent-skills repo path")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    args = parser.parse_args()

    db_path = Path(args.db).expanduser()
    skills_dir = Path(args.skills_dir).expanduser()
    output_path = Path(args.output).expanduser()

    conn = sqlite3.connect(str(db_path))
    now = datetime.now(timezone.utc)
    cutoff = (now - timedelta(days=ANALYSIS_WINDOW_DAYS)).isoformat()
    end_date = now.strftime("%Y-%m-%d")
    start_date = (now - timedelta(days=ANALYSIS_WINDOW_DAYS)).strftime("%Y-%m-%d")

    # Load current skills
    current_skills = load_skills(skills_dir)
    all_skill_names = get_all_skill_names(current_skills)

    # Run all pattern detection queries
    summary = get_session_summary(conn, cutoff)
    analysis = {
        "analysis_period": f"{start_date} ~ {end_date}",
        "total_sessions": summary["total_sessions"],
        "unique_projects": summary["unique_projects"],
        "unique_machines": summary["unique_machines"],
        "patterns": {
            "new_skill_candidates": detect_new_skill_candidates(conn, cutoff),
            "improvement_candidates": detect_improvement_candidates(conn, cutoff),
            "usage_stats": detect_usage_stats(conn, cutoff),
            "unused_skills": detect_unused_skills(conn, cutoff, all_skill_names),
            "tool_trends": detect_tool_trends(conn, cutoff),
        },
        "current_skills": current_skills,
        "recent_intents_sample": get_recent_intents_sample(conn, cutoff),
    }

    conn.close()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(analysis, f, indent=2, ensure_ascii=False)

    print(f"Analysis input written to {output_path}", file=__import__("sys").stderr)


if __name__ == "__main__":
    main()
