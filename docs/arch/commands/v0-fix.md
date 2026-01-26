# v0-fix

**Purpose:** Sequential bug fix worker.

## Workflow

**Start worker:**
1. Create worktree at `${V0_DEVELOP_BRANCH}-bugs` branch (e.g., `v0/agent/alice-a3f2-bugs`)
2. Setup hooks and helper scripts
3. Start polling loop and launch Claude in tmux

**Worker loop:**
1. Poll for bugs with `wk ready --type bug`
2. Run `./new-branch <id>` to reset to main
3. Claude implements the fix
4. Run `./fixed <id>` to push, queue merge, close issue
5. Exit session and repeat

## Usage

```bash
v0 fix "Button not working"   # Report a bug
v0 fix --start                # Start worker
v0 fix --stop                 # Stop worker
v0 fix --status               # Show status
v0 fix --logs                 # Show logs
v0 fix --history              # Show completed
```
