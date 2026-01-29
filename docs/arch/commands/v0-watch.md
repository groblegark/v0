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
v0 watch --all          # Watch all running projects on system
```

## System-wide Watch (--all)

The `--all` flag monitors all running v0 projects on the system:

```bash
v0 watch --all          # Watch all projects
v0 watch --all -n 10    # 10 second refresh
```

Projects are automatically registered when any v0 command runs (`v0 start`, `v0 build`, etc.). Registration is stored in `~/.local/state/v0/${PROJECT}/.v0.root`.

A project is considered "running" if it has:
- Active tmux sessions matching `v0-${PROJECT}-*`
- Running daemon processes (mergeq, fix, chore workers)

Press Ctrl+C to exit.
