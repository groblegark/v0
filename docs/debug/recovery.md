# Failure Recovery Runbook

Quick recovery procedures for common failure scenarios.

---

## Finding Lost Work

When work disappears, check these locations in order:

```bash
# 1. Remote branches not merged to main
git fetch origin
git branch -r --no-merged main | grep -E 'feature/|fix/|chore/'

# 2. Local worktrees with commits
for wt in BUILD_DIR/worktrees/*/*; do
  [ -d "$wt/.git" ] || continue
  ahead=$(git -C "$wt" rev-list --count main..HEAD 2>/dev/null)
  [ "$ahead" -gt 0 ] && echo "$wt: $ahead commits ahead"
done

# 3. Merge queue entries
v0 mergeq --list

# 4. Operation state files
find BUILD_DIR -name "state.json" -exec grep -l '"merged":false' {} \;

# 5. Git reflog (last resort for deleted worktrees)
git reflog | grep -E 'feature/|fix/|chore/'
```

---

## Branch Lost - Never Merged

**Symptoms:**
- Branch exists on remote but never merged to main
- Operation shows `pending_merge` or `completed` state

**Diagnosis:**
```bash
# Check merge queue
v0 mergeq --list | grep {name}

# Check operation state
cat BUILD_DIR/operations/{name}/state.json | jq '{phase, merged, merge_queued}'

# Check remote branch
git ls-remote origin feature/{name}
```

**Recovery:**
```bash
# If not in queue, re-enqueue
v0 mergeq --enqueue {name}

# If queue daemon not running
v0 mergeq --start

# If worktree deleted, manual merge
git fetch origin
git checkout main
git merge origin/feature/{name}
git push origin main
```

---

## Agent Exited With Incomplete Work

**Symptoms:**
- Issues still open but agent exited cleanly
- Work committed but branch never merged
- No error messages

**Cause:** Stop hook failed to block exit. See [hooks.md](hooks.md#1-hook-silently-approves-exit-critical).

**Diagnosis:**
```bash
# Check if wk is working
wk list --label "plan:{name}" --status todo
echo $?  # non-zero means wk broken

# Check what's on the branch
git -C BUILD_DIR/worktrees/feature/{name} log --oneline main..HEAD
```

**Recovery:**
```bash
# Resume the feature
v0 feature {name} --resume

# Or manually close issues and merge
wk done {issue_id}
v0 mergeq --enqueue {name}
```

---

## User Force-Killed Stuck Session

**Symptoms:**
- tmux session killed manually
- Uncommitted changes may be lost
- Work partially complete

**Diagnosis:**
```bash
# Check if branch was pushed
git ls-remote origin feature/{name}

# Check worktree state (if exists)
git -C BUILD_DIR/worktrees/feature/{name} status
git -C BUILD_DIR/worktrees/feature/{name} stash list

# Check reflog for lost commits
git -C BUILD_DIR/worktrees/feature/{name} reflog
```

**Recovery:**
```bash
# If worktree exists with uncommitted changes
cd BUILD_DIR/worktrees/feature/{name}
git add . && git commit -m "WIP: recovered after force-kill"
git push -u origin HEAD

# Resume feature to complete
v0 feature {name} --resume
```

---

## Partial Completion (fixed/done Failed Mid-Way)

**Symptoms:**
- Branch pushed but not in merge queue
- Or: merged but issue still open
- Or: not pushed at all

**Diagnosis:**
```bash
# What succeeded?
git ls-remote origin fix/{id}           # push?
v0 mergeq --list | grep {id}            # enqueue?
wk show {id} | grep status              # wk done?
```

**Recovery:**
```bash
# Pushed but not enqueued
v0 mergeq --enqueue fix/{id}

# Merged but issue still open
wk done {id}

# Not pushed - find worktree
git -C BUILD_DIR/fix/{id}/worktree push -u origin HEAD
v0 mergeq --enqueue fix/{id}
```

---

## Merge Queue Daemon Stopped

**Symptoms:**
- Operations pile up in `pending_merge`
- No merge activity

**Diagnosis:**
```bash
pgrep -f "v0-mergeq --watch"
tail BUILD_DIR/mergeq/daemon.log
```

**Recovery:**
```bash
v0 mergeq --start
```

---

## Open Issues Blocking Merge

**Symptoms:**
- Operation in queue but not processing
- State shows `merge_resumed=true`

**Diagnosis:**
```bash
wk ls --label "plan:{name}" --status open
```

**Recovery:**
```bash
# Option 1: Resume feature to close issues
v0 feature {name} --resume

# Option 2: Close issues manually
wk done {issue_id}
```

---

## Worktree Deleted Before Merge

**Symptoms:**
- Queue entry shows `status=failed`
- Remote branch still exists

**Diagnosis:**
```bash
# Check worktree path from queue
cat BUILD_DIR/mergeq/queue.json | jq '.entries[] | select(.operation == "{name}") | .worktree'

# Verify branch on remote
git ls-remote origin feature/{name}
```

**Recovery:**
```bash
# Option 1: Recreate worktree
git worktree add BUILD_DIR/worktrees/feature/{name} origin/feature/{name}
v0 mergeq --enqueue {name}

# Option 2: Manual merge
git checkout main && git merge origin/feature/{name} && git push
```

---

## Worker Daemon Crashed (fix/chore)

**Symptoms:**
- No bugs/chores being processed
- tmux session dead or stuck

**Diagnosis:**
```bash
tmux ls | grep worker
ls BUILD_DIR/fix/*/alert 2>/dev/null   # check for alert markers
ls BUILD_DIR/chore/*/alert 2>/dev/null
```

**Recovery:**
```bash
# Restart workers
v0 fix --start
v0 chore --start
```

---

## Feature Agent Stuck/Crashed

**Symptoms:**
- Feature in `executing` state indefinitely
- tmux session dead or unresponsive

**Diagnosis:**
```bash
tmux ls | grep "feature-{name}"
cat BUILD_DIR/operations/{name}/state.json | jq .phase
```

**Recovery:**
```bash
# Resume the feature
v0 feature {name} --resume

# Or attach to debug
tmux attach -t {project}-feature-{name}
```

---

## Merge Conflict

**Symptoms:**
- Queue entry shows `status=conflict`

**Diagnosis:**
```bash
v0 mergeq --list | grep conflict
```

**Recovery:**
```bash
# Go to worktree
cd BUILD_DIR/worktrees/feature/{name}

# Resolve conflicts
git status
# ... edit conflicting files ...
git add .
git commit -m "Resolve merge conflicts"

# Retry merge
v0 mergeq --retry {name}
```

---

## Lock File Stuck

**Symptoms:**
- Commands hang waiting for lock
- No active process holding lock

**Diagnosis:**
```bash
ls -la BUILD_DIR/.merge.lock BUILD_DIR/mergeq/.queue.lock 2>/dev/null
pgrep -f "v0-mergeq"
```

**Recovery:**
```bash
# Only if no daemon running
pgrep -f "v0-mergeq" || rm BUILD_DIR/.merge.lock BUILD_DIR/mergeq/.queue.lock
```

---

## Hook Blocking Incorrectly

**Symptoms:**
- Agent can't exit, says issues remain
- But issues appear closed in `wk`

**Cause:** Stale cache or hook seeing different data.

**Diagnosis:**
```bash
# Compare what hook sees vs reality
wk list --label "plan:{name}" --status todo      # hook's query
wk list --label "plan:{name}"                     # all statuses
wk sync                                           # refresh if available
```

**Recovery:**
```bash
# Force close any stuck issues
wk ls --label "plan:{name}" | grep -v done | xargs -I{} wk done {}

# Or set stop_hook_active to bypass (careful!)
# Agent will need to be restarted with special flag
```

See [hooks.md](hooks.md) for detailed hook debugging.

---

## Quick Reference: State Locations

| Workflow | State File |
|----------|------------|
| Feature | `BUILD_DIR/operations/{name}/state.json` |
| Fix | `BUILD_DIR/fix/{id}/state.json` |
| Chore | `BUILD_DIR/chore/{id}/state.json` |
| Queue | `BUILD_DIR/mergeq/queue.json` |

## Quick Reference: Where Work Can Hide

| Location | Check Command |
|----------|---------------|
| Remote branches | `git branch -r --no-merged main` |
| Local worktrees | `git worktree list` |
| Merge queue | `v0 mergeq --list` |
| State files | `find BUILD_DIR -name state.json` |
| Git reflog | `git reflog` |
| Stashed changes | `git -C {worktree} stash list` |
