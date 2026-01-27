# v0-shutdown

**Purpose:** Stop all v0 workers, daemons, and sessions for the current project.

This is the underlying implementation for `v0 stop` when called without arguments.

## Workflow

1. Terminate all tmux sessions for this project
2. Kill polling daemons
3. Reopen in-progress issues
4. Remove worker worktrees (v0-*-worker)
5. Delete worker branches (*-bugs, *-chores, v0/worker/*)
6. Stop coffee and nudge daemons

## Usage

```bash
v0 stop                       # Stop all workers
v0 stop --force               # Force kill, delete unmerged branches
v0 stop --dry-run             # Preview what would be stopped
v0 stop --drop-workspace      # Also remove workspace and worktrees
v0 stop --drop-everything     # Full reset (removes all v0 state)
```

## Options

| Option | Description |
|--------|-------------|
| `--force` | Force kill and delete branches with unmerged commits |
| `--drop-workspace` | Also remove workspace and all worktrees |
| `--drop-everything` | Full reset: remove workspace, build state, and agent remote |
| `--dry-run` | Show what would be stopped without stopping |

## Cleanup Levels

| Option | Removes |
|--------|---------|
| (default) | Sessions, daemons, worker branches/worktrees |
| `--drop-workspace` | + `~/.local/state/v0/${PROJECT}/workspace/` and `tree/` |
| `--drop-everything` | + `~/.local/state/v0/${PROJECT}/`, `.v0/`, and `agent` remote |

## Related

- [v0-startup](v0-startup.md) - Start all workers
- [v0-stop](v0-stop.md) - Stop individual workers
