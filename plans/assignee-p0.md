# Implementation Plan: Assignee P0

## Overview

Add assignee tracking to the v0 worker system so that issues are properly assigned to the worker currently processing them (`worker:fix`, `worker:chore`, `worker:mergeq`). During shutdown, any in-progress issues owned by the shutting-down worker should be moved back to open status.

This enables better visibility into which worker is handling which issues and ensures issues don't get stuck in "in_progress" state when workers are shut down.

## Project Structure

Files to modify:
```
bin/v0-fix       # Add assignee to new-branch, write .wok/current/assignee
bin/v0-chore     # Add assignee to new-branch, write .wok/current/assignee
bin/v0-mergeq    # Set assignee to worker:mergeq when dequeuing
bin/v0-shutdown  # Reopen in-progress issues owned by shut-down workers
```

New files:
```
.wok/current/assignee   # Created in worktree, contains worker role (e.g., "worker:fix")
```

## Dependencies

- `wk` CLI tool with `-a/--assignee` support (already available)
- Existing v0 infrastructure (worktrees, mergeq, shutdown)

## Implementation Phases

### Phase 1: Add Assignee File to Worktree Configuration

When configuring a worktree in `v0-fix` and `v0-chore`, write the worker role to `.wok/current/assignee`.

**v0-fix** (after line 116 where `wk init` is called):
```bash
# Write worker assignee role for this worktree
mkdir -p "${tree_dir}/.wok/current"
echo "worker:fix" > "${tree_dir}/.wok/current/assignee"
```

**v0-chore** (after line 116 where `wk init` is called):
```bash
# Write worker assignee role for this worktree
mkdir -p "${tree_dir}/.wok/current"
echo "worker:chore" > "${tree_dir}/.wok/current/assignee"
```

**Verification**: After starting a worker, check that `.wok/current/assignee` exists in the worktree with the correct content.

---

### Phase 2: Set Assignee in new-branch Script

When `new-branch` claims an issue, set the assignee to the current worker role.

**v0-fix** `new-branch` script (add after recording state in `state.json`, around line 243):
```bash
# Set assignee to this worker
wk edit "\$BUG_ID" assignee "worker:fix"
```

**v0-chore** `new-branch` script (add after recording state in `state.json`, around line 194):
```bash
# Set assignee to this worker
wk edit "\$CHORE_ID" assignee "worker:chore"
```

Alternative implementation using the assignee file:
```bash
# Read assignee from worktree config
ASSIGNEE=\$(cat "\${SCRIPT_DIR}/.wok/current/assignee" 2>/dev/null || echo "")
if [[ -n "\$ASSIGNEE" ]]; then
  wk edit "\$BUG_ID" assignee "\$ASSIGNEE"
fi
```

**Verification**: After running `./new-branch <id>`, check `wk show <id>` shows correct assignee.

---

### Phase 3: Set Assignee to worker:mergeq on Queue

When an issue is queued for merge, change the assignee to `worker:mergeq`.

**v0-fix** `fixed` script (add after the `v0-mergeq --enqueue` call, around line 289):
```bash
# Transfer ownership to merge queue
wk edit "\$BUG_ID" assignee "worker:mergeq"
```

**v0-chore** `fixed` script (add after the `v0-mergeq --enqueue` call, around line 240):
```bash
# Transfer ownership to merge queue
wk edit "\$CHORE_ID" assignee "worker:mergeq"
```

Also in the **v0-fix** `new-branch` script where it handles completing a previous fix (around line 219-223):
```bash
# Queue for merge
"${V0_DIR}/bin/v0-mergeq" --enqueue "\$PREV_BRANCH" --issue-id "\$PREV_BUG_ID"

# Transfer ownership to merge queue
wk edit "\$PREV_BUG_ID" assignee "worker:mergeq"

# Close the bug
wk done "\$PREV_BUG_ID"
```

**Verification**: After running `./fixed <id>`, check `wk show <id>` shows assignee as `worker:mergeq`.

---

### Phase 4: Reopen In-Progress Issues on Shutdown

Modify `v0-shutdown` to find and reopen any in-progress issues owned by the workers being shut down.

Add this logic AFTER stopping tmux sessions and daemons (around line 124), but BEFORE worktree cleanup:

```bash
# Reopen in-progress issues owned by workers being shut down
echo ""
echo "Checking for in-progress issues to reopen..."

# Define workers to check
WORKERS=("worker:fix" "worker:chore")

for worker in "${WORKERS[@]}"; do
  # Find in-progress issues assigned to this worker
  issues=$(wk list --status in_progress --assignee "${worker}" -f json 2>/dev/null | jq -r '.[].id' || true)

  if [[ -n "${issues}" ]]; then
    while IFS= read -r issue_id; do
      [[ -z "${issue_id}" ]] && continue

      if [[ -n "${DRY_RUN}" ]]; then
        echo "Would reopen: ${issue_id} (was assigned to ${worker})"
      else
        echo "Reopening: ${issue_id} (was assigned to ${worker})"
        wk stop "${issue_id}" 2>/dev/null || true
        wk edit "${issue_id}" assignee none 2>/dev/null || true
      fi
    done <<< "${issues}"
  fi
done
```

**Key considerations**:
- Use `wk stop` to move from `in_progress` back to `todo` status
- Clear the assignee so the issue can be picked up by another worker
- Run AFTER stopping sessions so workers don't interfere
- Run BEFORE worktree cleanup so `.wok` is still accessible

**Verification**:
1. Start a fix worker: `v0 fix --start`
2. Add a bug: `v0 fix "Test bug"`
3. Wait for worker to pick it up (check `v0 fix --status`)
4. Run `v0 shutdown`
5. Verify the issue is now in `todo` status with no assignee: `wk list -s todo`

---

### Phase 5: Handle mergeq Assignee on Completion (Optional Enhancement)

When mergeq successfully merges a branch, the issue is already closed by `wk done`. However, for failed/conflict merges, we may want to reassign or clear the assignee.

In `v0-mergeq` `process_branch_merge` function, after a conflict or failure:
```bash
# On conflict/failure, clear assignee so issue can be manually handled
local issue_id
issue_id=$(get_issue_id "${branch}")
if [[ -n "${issue_id}" ]]; then
  wk edit "${issue_id}" assignee none 2>/dev/null || true
fi
```

**Note**: This is a lower priority enhancement since conflicts require manual intervention anyway.

---

## Key Implementation Details

### Assignee Naming Convention

| Worker Type | Assignee Value |
|-------------|----------------|
| Fix worker | `worker:fix` |
| Chore worker | `worker:chore` |
| Merge queue | `worker:mergeq` |

The `worker:` prefix clearly identifies automated workers vs. human assignees.

### Assignee File Location

The `.wok/current/assignee` file is placed inside the worktree's `.wok` directory because:
1. It's already a linked workspace (`wk init --workspace`)
2. The `current/` subdirectory clearly indicates runtime state
3. It won't conflict with the shared workspace database

### Issue State Transitions

```
[todo] --(worker picks up)--> [in_progress, assignee:worker:fix]
       --(worker completes)--> [in_progress, assignee:worker:mergeq]
       --(mergeq merges)-----> [done, assignee:worker:mergeq]

[in_progress] --(shutdown)--> [todo, assignee:none]
```

### Race Condition Handling

The shutdown sequence is designed to avoid races:
1. Stop tmux sessions (worker can no longer start new work)
2. Stop polling daemons (no new sessions will launch)
3. Stop mergeq daemon (no new merges will start)
4. **Reopen in-progress issues** (safe because workers are stopped)
5. Clean up worktrees

---

## Verification Plan

### Unit Tests (tests/unit/)

Add tests to verify:
1. `new-branch` script sets correct assignee
2. `fixed` script changes assignee to `worker:mergeq`
3. `.wok/current/assignee` file is created with correct content
4. Shutdown reopens in-progress issues for the correct workers

### Manual Testing Checklist

- [ ] Start fix worker, verify `.wok/current/assignee` contains `worker:fix`
- [ ] Report bug, watch worker pick it up, verify assignee is `worker:fix`
- [ ] Watch worker complete bug, verify assignee changes to `worker:mergeq`
- [ ] Start chore worker, verify same flow with `worker:chore`
- [ ] With worker active on a bug, run `v0 shutdown`
- [ ] Verify in-progress bug is now in `todo` status with no assignee
- [ ] Verify `v0 shutdown --dry-run` shows what would be reopened

### Integration Test Scenarios

1. **Normal flow**: Bug created -> picked up -> fixed -> merged
   - Assignee transitions: none -> worker:fix -> worker:mergeq -> (done)

2. **Shutdown during work**: Bug in progress, worker shutdown
   - Assignee transitions: worker:fix -> none (with status back to todo)

3. **Multiple workers**: Both fix and chore workers running, shutdown all
   - Each worker's in-progress issues should be reopened independently
