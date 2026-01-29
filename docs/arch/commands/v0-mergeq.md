# v0-mergeq

**Purpose:** Merge queue daemon for processing merges sequentially.

See [mergeq/state.md](../mergeq/state.md) for state machine, queue schema, and processing details.

## Usage

```bash
v0 mergeq --start                           # Start daemon in background
v0 mergeq --stop                            # Stop daemon
v0 mergeq --status                          # Show daemon status
v0 mergeq --list                            # List queue entries
v0 mergeq --enqueue feature/auth            # Add branch to queue
v0 mergeq --enqueue auth --issue-id PROJ-x  # With issue tracking
```

## Log Files

- Daemon log: `.v0/build/mergeq/logs/daemon.log`
- Merge log: `.v0/build/mergeq/logs/merge.log`

## Auto-Start

Started automatically by `v0 startup` or first `--enqueue` call.
