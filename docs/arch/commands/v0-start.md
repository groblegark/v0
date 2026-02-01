# v0-start

**Purpose:** Start v0 workers (individual or all).

## Usage

```bash
# Start individual workers
v0 start fix           # Start the fix worker
v0 start chore         # Start the chore worker
v0 start mergeq        # Start the merge queue daemon

# Start all workers
v0 start               # Start all workers
v0 start --dry-run     # Preview what would be started
```

## Workflow (start all)

1. Start fix worker
2. Start chore worker
3. Start merge queue daemon
4. Start coffee and nudge daemons

## Related

- [v0-stop](v0-stop.md) - Stop workers
