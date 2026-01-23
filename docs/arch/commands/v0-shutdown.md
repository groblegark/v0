# v0-shutdown

**Purpose:** Stop all v0 workers for the project.

## Workflow

1. Kill all v0 tmux sessions
2. Stop merge queue daemon
3. Reopen in-progress issues
4. Remove worker worktrees and branches
5. Stop coffee and nudge daemons

## Usage

```bash
v0 shutdown              # Stop all
v0 shutdown --dry-run    # Preview
v0 shutdown --force      # Force kill, delete unmerged branches
```
