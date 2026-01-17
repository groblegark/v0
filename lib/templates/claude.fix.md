# Bug Fix Worker

You are fixing ONE bug per session, then exiting to keep context windows small.

## Workflow

1. **Find a bug**: `wk ready --type bug` to see available bugs
2. **If a bug is available**:
   - Claim bug: `wk start <id>`
   - Create branch: `./new-branch <id>` - creates `fix/<id>` branch from main
   - Understand: `wk show <id>` to read the bug details
   - Fix: Read code, make changes, test
   - Commit: `cd <repo-name> && git add <files> && git commit -m "Fix: ..."`
   - Complete: `./fixed <id>` - pushes, queues merge, closes bug, **exits session**
3. **If no bugs available**: Run `./done` (or `../done` from worktree dir) to exit cleanly

The polling manager will detect the exit and relaunch automatically for the next bug.

## Helper Scripts

- `./new-branch <id>` - Reset worktree to latest main, ready to fix
- `./fixed <id>` - Push as `fix/<id>`, queue merge, close bug, **exit session**
- `./done` (or `../done` from worktree dir) - Exit when no bugs available

## Example Session

```bash
wk ready --type bug
# proj-abc1: Button color wrong

wk start proj-abc1
./new-branch proj-abc1
# Reset to latest main
# Ready to fix proj-abc1

wk show proj-abc1
# ... read and understand ...

# ... make fixes ...

cd <repo-name> && git add src/button.rs && git commit -m "Fix: correct button color"
./fixed proj-abc1
# Pushing fix/proj-abc1...
# Queueing for merge...
# Closing proj-abc1...
# Resetting to latest main...
#
# Completed proj-abc1
# Branch fix/proj-abc1 queued for merge
# Exiting session...
# (session ends here - polling manager will launch new session for next bug)
```

## Important Notes

- **One bug per session** - keeps context windows small and costs low
- Each bug gets its own branch - fixes are isolated
- Merges happen automatically via merge queue
- If merge fails, it doesn't block other bugs
- If you cannot fix a bug, add a note with `wk note <id> "reason"` and move on
- Always use `./fixed` to complete - it handles the merge queue and exits
- The polling manager will relaunch for each new bug
