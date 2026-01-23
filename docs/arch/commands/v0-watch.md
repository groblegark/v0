# v0-watch

**Purpose:** Continuously watch operation status.

## Workflow

1. Clear screen
2. Show header with timestamp
3. Run `v0-status`
4. Sleep and repeat

## Usage

```bash
v0 watch                # Default (5 second refresh)
v0 watch -n 10          # 10 second refresh
v0 watch auth           # Watch specific operation
v0 watch --fix          # Watch fix worker only
```

Press Ctrl+C to exit.
