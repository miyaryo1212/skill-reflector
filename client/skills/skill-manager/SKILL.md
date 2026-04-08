---
name: skill-manager
description: Manage agent skills — sync, create, list, update, delete, log, status. Use when the user wants to manage their skills or when invoked as /skill-manager.
---

You are skill-manager, the central management skill for skill-reflector.
Read the .env file from the skill-reflector installation directory to get configuration.

## Finding the .env file

The skill-reflector installation directory can be determined by resolving this SKILL.md file's real path (follow symlinks) and navigating to the repo root. Specifically:

1. This SKILL.md is symlinked from the skill-reflector repo at `client/skills/skill-manager/SKILL.md`
2. The .env file is at the repo root: `<skill-reflector-repo>/.env`
3. To find it, resolve the symlink of this skill's directory and go up 3 levels: `client/skills/skill-manager/` → repo root

Use `readlink -f` on this skill's path to find the actual location, then load `.env` from the repo root.

## Subcommands

Parse the user's input to determine which subcommand to run. If no subcommand is given, show available subcommands.

### sync

Sync skills from the agent-skills repo to the current project.

Steps:
1. Load .env to get `SKILLS_LOCAL_PATH`
2. Run `git -C $SKILLS_LOCAL_PATH pull --quiet` (ignore errors gracefully)
3. Read `.skill-reflector.yaml` in the current project root to get declared namespaces
4. Determine the target skills directory:
   - If `~/.claude/` exists: target is both `~/.claude/skills/` (global) and `.claude/skills/` (project)
   - If `~/.codex/` exists: target is both `~/.codex/skills/` (global) and `.agents/skills/` (project)
5. For global skills (`$SKILLS_LOCAL_PATH/global/`):
   - For each subdirectory, create a symlink in the global skills directory
6. For namespace skills:
   - For each namespace declared in `.skill-reflector.yaml`
   - For each skill in `$SKILLS_LOCAL_PATH/namespaces/<namespace>/`
   - Create a symlink in the project skills directory
7. Report what was synced

### create

Create a new skill and register it in the agent-skills repo.

Steps:
1. Ask the user: skill name, description, and whether it's global or belongs to a namespace
2. If namespace, ask which namespace (existing or new)
3. Create the skill directory with SKILL.md using the template from `<skill-reflector-repo>/client/templates/skill-template.md`
4. Place it in the correct location in `$SKILLS_LOCAL_PATH` (global/ or namespaces/<ns>/)
5. Create a symlink in the appropriate skills directory
6. Create a branch in agent-skills repo, commit, and push
7. Create a PR using `gh pr create`
8. After creation, scan the current project's skills directories for any unregistered skills (files/directories that are not symlinks pointing to agent-skills repo) and offer to register them

### list

List all managed skills and their status.

Steps:
1. Load .env to get `SKILLS_LOCAL_PATH`
2. List global skills from `$SKILLS_LOCAL_PATH/global/`
3. List namespace skills from `$SKILLS_LOCAL_PATH/namespaces/`
4. Check the current project's skills directories for unregistered skills (not symlinked to agent-skills repo)
5. Display as a formatted table showing: name, scope (global/namespace), status (registered/unregistered)

### update

Update an existing skill.

Steps:
1. Let the user select which skill to update (from list)
2. Read the current SKILL.md content
3. Let the user describe the changes or edit directly
4. Update the file in `$SKILLS_LOCAL_PATH`
5. Create a branch, commit, push, and create a PR in agent-skills repo

### delete

Delete a skill.

Steps:
1. Let the user select which skill to delete
2. Confirm deletion
3. Remove the symlink from skills directories
4. Create a branch, remove the skill directory from `$SKILLS_LOCAL_PATH`, commit, push, and create a PR

### log

Record and send the current session log.

Steps:
1. Load .env to get `LOG_SERVER`, `LOG_SERVER_PATH`, `MACHINE_NAME`, `SERVER_ENABLED`
2. Find the current session's log file:
   - Claude Code: `~/.claude/projects/<project>/` (most recent .jsonl file)
   - Codex: `~/.codex/sessions/YYYY/MM/DD/` (most recent rollout-*.jsonl)
3. Copy the session log to a structured location:
   - Generate filename: `<MACHINE_NAME>_<timestamp>.jsonl`
4. Send/store based on mode:
   - `SERVER_ENABLED=false`: `scp <logfile> $LOG_SERVER:$LOG_SERVER_PATH/$MACHINE_NAME/`
   - `SERVER_ENABLED=true`: `cp <logfile> $LOG_SERVER_PATH/$MACHINE_NAME/`
5. Report success/failure

### status

Show the current project's skill-reflector status.

Steps:
1. Show which agent is detected (Claude Code / Codex)
2. Show .env configuration summary
3. Show synced global skills count
4. Show synced namespace skills for this project
5. Show any unregistered skills
6. Show last log submission timestamp (if available)
