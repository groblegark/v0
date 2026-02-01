# v0-coffee

**Purpose:** Keep system awake during long-running operations.

## Workflow

1. Start: Launch `caffeinate` in background with timeout
2. Stop: Kill `caffeinate` process
3. Status: Check PID file

## Usage

```bash
v0 coffee              # Start (2 hours, background)
v0 coffee 4            # Start for 4 hours
v0 coffee stop         # Stop
v0 coffee status       # Check if running
v0 coffee --foreground # Run interactively (blocks)
```

## Options

`--display` prevent display sleep, `--system` prevent system sleep
