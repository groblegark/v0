# v0-prune

**Purpose:** Clean up old operation state and logs.

## Workflow

1. Find operations in terminal states (`merged`, `cancelled`)
2. Remove state directories
3. Prune old merge queue entries (>6 hours)
4. Prune old log entries

## Usage

```bash
v0 prune              # Prune completed/cancelled
v0 prune auth         # Prune specific operation
v0 prune --all        # Prune all (with confirmation)
v0 prune --dry-run    # Preview what would be pruned
```
