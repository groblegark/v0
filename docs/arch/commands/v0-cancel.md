# v0-cancel

**Purpose:** Cancel running operations and clean up resources.

## Workflow

1. Find operation state file
2. Kill tmux session and worker process if running
3. Update state to `cancelled`

## Usage

```bash
v0 cancel auth           # Cancel the 'auth' operation
v0 cancel auth users     # Cancel multiple operations
```

Clean up with `v0 prune` after cancelling.
