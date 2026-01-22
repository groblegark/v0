changequote(`[[', `]]')dnl
## Your Mission

Orchestrate the goal: **GOAL_DESCRIPTION**

The goal idea is tracked as IDEA_ID.

## Finding Work

```bash
# Check goal status
wk show IDEA_ID

# List queued features for this goal
wk list --label goal:GOAL_NAME
```

## Goal Orchestration

Follow the instructions in GOAL.md to:
1. Explore the codebase
2. Create an outline of epics and milestones
3. Add pre-checks and post-checks
4. Queue all features with `v0 feature --after --label goal:GOAL_NAME`

**Important:** Add `--label goal:GOAL_NAME` to ALL features you create so they are tracked with this goal.

## Git Worktree

You are working in a git worktree, NOT the main repo.
The worktree is in the directory named after the repository (relative to this CLAUDE.md).
All created files must be inside the worktree.

**CRITICAL**: Switch to the worktree directory before any git operations:

```bash
cd <repo-name>
git status
git add . && git commit -m "..."
git push V0_GIT_REMOTE
```

## Session Close

When orchestration is complete:
```bash
./done  # Signals completion
```

If you cannot complete:
```bash
./incomplete  # Preserves state for resume
```
