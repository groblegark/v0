# v0-chore

**Purpose:** Sequential chore processing worker.

## Workflow

**Start worker:**
1. Create worktree at `v0/worker/chore` branch
2. Setup hooks and helper scripts
3. Start polling loop and launch Claude in tmux

**Worker loop:**
1. Poll for chores with `wk ready --type chore`
2. Run `./new-branch <id>` to reset to main
3. Claude implements the chore
4. Run `./fixed <id>` to push, queue merge, close issue
5. Exit session and repeat

## Usage

```bash
v0 chore "Update dependencies"   # Report a chore
v0 chore --start                 # Start worker
v0 chore --stop                  # Stop worker
v0 chore --status                # Show status
v0 chore --logs                  # Show logs
v0 chore --history               # Show completed
```

## Modes

- **Project mode**: Creates worktree, pushes branches, queues merges
- **Standalone mode**: No git/merge queue, works in current directory
