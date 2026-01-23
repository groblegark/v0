# v0-startup

**Purpose:** Start all v0 workers for the project.

## Workflow

1. Start fix worker
2. Start chore worker
3. Start merge queue daemon
4. Start coffee and nudge daemons

## Usage

```bash
v0 startup              # Start all workers
v0 startup fix          # Start only fix
v0 startup fix chore    # Start fix and chore
```
