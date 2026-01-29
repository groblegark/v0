# v0-startup

**Purpose:** Start all v0 workers for the current project.

This is the underlying implementation for `v0 start` when called without arguments.

## Workflow

1. Start specified workers (or all: fix, chore, mergeq)
2. Start coffee (system wake lock)
3. Start nudge (idle session monitor)

## Usage

```bash
v0 start                 # Start all workers
v0 start fix             # Start only the fix worker
v0 start fix chore       # Start fix and chore workers
v0 start --dry-run       # Preview what would be started
```

## Workers

| Worker | Description |
|--------|-------------|
| `fix` | Bug fix worker |
| `chore` | Chore worker |
| `mergeq` | Merge queue daemon |

## Automatic Daemons

When starting workers, these daemons are also started:
- **coffee** - Keeps system awake (default: 8 hours)
- **nudge** - Monitors for idle sessions

## Related

- [v0-shutdown](v0-shutdown.md) - Stop all workers
- [v0-start](v0-start.md) - Start individual workers
