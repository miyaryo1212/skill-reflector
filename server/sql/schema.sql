CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  machine TEXT NOT NULL,
  project TEXT,
  entrypoint TEXT,
  git_branch TEXT,
  title TEXT,
  started_at TEXT,
  ended_at TEXT,
  turn_count INTEGER DEFAULT 0,
  source_file TEXT NOT NULL,
  imported_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS skill_usages (
  session_id TEXT NOT NULL REFERENCES sessions(id),
  skill_name TEXT NOT NULL,
  invocation_count INTEGER DEFAULT 1,
  PRIMARY KEY (session_id, skill_name)
);

CREATE TABLE IF NOT EXISTS tool_usages (
  session_id TEXT NOT NULL REFERENCES sessions(id),
  tool_name TEXT NOT NULL,
  use_count INTEGER DEFAULT 0,
  PRIMARY KEY (session_id, tool_name)
);

CREATE TABLE IF NOT EXISTS user_intents (
  session_id TEXT NOT NULL REFERENCES sessions(id),
  turn_index INTEGER NOT NULL,
  intent_text TEXT,
  timestamp TEXT,
  PRIMARY KEY (session_id, turn_index)
);

CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_sessions_machine ON sessions(machine);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project);
CREATE INDEX IF NOT EXISTS idx_skill_usages_skill ON skill_usages(skill_name);
