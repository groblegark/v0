# v0-attach

**Purpose:** Attach to running tmux sessions for workers or operations.

## Workflow

1. Parse target type (fix, chore, mergeq, feature, roadmap)
2. Determine session name from state or derive from phase
3. Attach to tmux session if it exists

## Usage

```bash
v0 attach fix                # Attach to fix worker
v0 attach chore              # Attach to chore worker
v0 attach mergeq             # Attach to merge resolution
v0 attach feature auth       # Attach to feature session
v0 attach auth               # Shorthand for above
v0 attach --list             # List all v0 sessions
```
