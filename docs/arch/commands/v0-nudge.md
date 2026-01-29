# v0-nudge

**Purpose:** Monitor for idle Claude sessions and send nudges.

## Workflow

1. Find all v0 tmux sessions
2. Check time since last output
3. If idle beyond threshold, send nudge input
4. Repeat on interval

## Usage

```bash
v0 nudge start    # Start daemon
v0 nudge stop     # Stop daemon
v0 nudge status   # Check if running
```

Auto-started by `v0 startup` and worker start commands.
