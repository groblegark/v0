# Fix: False Positive "Merged" Status in v0 status

## Overview

`v0 status` occasionally displays operations as "merged" before the code is actually merged to main. This plan identifies root causes and implements verification to ensure the "merged" status only appears when commits are truly on the main branch.

## Project Structure

Key files involved:

```
bin/
  v0-merge      # Performs the actual merge, updates state
  v0-mergeq     # Merge queue daemon, also updates state
  v0-status     # Reads and displays merge status
lib/
  state-machine.sh  # sm_transition_to_merged(), state management
tests/unit/
  v0-merge.bats     # Existing merge tests
  v0-status.bats    # Status display tests
  v0-mergeq.bats    # Queue tests
```

State files:
- `${BUILD_DIR}/operations/${op}/state.json` - Operation state with `phase`, `merge_status`, `merged_at`
- `${BUILD_DIR}/mergeq/queue.json` - Queue entries with `status` field

## Dependencies

- `git` - For commit verification
- `jq` - For JSON state file manipulation
- Existing v0 infrastructure (no new dependencies needed)

## Merge Workflows

Understanding the merge strategy is critical for verification. `v0-merge` uses a tiered approach in `do_merge()` (lines 320-346):

### Workflow 1: Direct Fast-Forward

```bash
git merge --ff-only "${BRANCH}"
```

- Branch commits move directly onto main with same hashes
- `HEAD` after merge = original branch tip commit
- **Verification**: Branch commit IS an ancestor of main ✓

### Workflow 2: Rebase + Fast-Forward

```bash
git -C "${WORKTREE}" rebase origin/main
git merge --ff-only "${BRANCH}"
```

- Branch is rebased onto origin/main, creating **new commit hashes**
- Then fast-forwarded onto main
- `HEAD` after merge = rebased commit (new hash, different from original)
- **Verification challenge**: Original branch commits are NOT ancestors of main
- After `cleanup()`, branch is deleted - can't check by branch name

### Workflow 3: Merge Commit (Fallback)

```bash
git merge --no-edit "${BRANCH}"
```

- Creates a merge commit combining histories
- `HEAD` after merge = new merge commit
- Original branch commits ARE ancestors of the merge commit
- **Verification**: Branch commits are ancestors of main ✓

### Verification Implications

| Workflow | `git rev-parse HEAD` after merge | Original branch on main? |
|----------|----------------------------------|--------------------------|
| Direct FF | Same as branch tip | Yes |
| Rebase+FF | New rebased commit | **No** (different hashes) |
| Merge commit | New merge commit | Yes (as ancestors) |

**Key insight**: Only `HEAD` captured immediately after `do_merge()` reliably identifies what's on main. Checking the original branch name fails for rebase merges.

## Root Cause Analysis

### Cause 1: No Verification That Commit Exists on Main

**Location:** `bin/v0-merge:569` and `bin/v0-mergeq:825-832`

The current flow marks status as "merged" when `v0-merge` exits 0, but doesn't verify:
1. The merge commit actually exists on the main branch
2. The merge commit has been pushed to `origin/main`

```bash
# Current code in v0-mergeq (lines 825-832)
if [[ ${merge_exit} -eq 0 ]]; then
  # Success - immediately marks as merged without verification
  update_entry "${op}" "completed"
  update_operation_state "${op}" "merge_status" '"merged"'
  update_operation_state "${op}" "merged_at" "\"${merged_at}\""
  update_operation_state "${op}" "phase" '"merged"'
```

### Cause 2: Queue Entry Updated Before State File

**Location:** `bin/v0-mergeq:829-832`

Queue is marked "completed" before `state.json` is updated. If `v0-status` reads between these updates:
```bash
update_entry "${op}" "completed"           # Line 829 - queue shows completed
update_operation_state "${op}" ...         # Lines 830-832 - state still stale
```

### Cause 3: Duplicate State Updates Create Race Conditions

**Location:** `bin/v0-merge:154-178` and `bin/v0-mergeq:825-858`

Both `v0-merge` and `v0-mergeq` update state independently:
- `v0-merge` calls `update_operation_state()` (line 569)
- `v0-merge` calls `update_merge_queue_entry()` (line 569)
- `v0-mergeq` also calls `update_entry()` and `update_operation_state()` (lines 829-832)

### Cause 4: Silent Push Failures

**Location:** `bin/v0-merge:569`

If `git push` fails but the local merge succeeded, the chain `do_merge && cleanup && git push && update_*` stops, but local main has the commits. A subsequent status check might show "merged" based on branch comparison.

### Cause 5: Stale Queue Entries

If an operation was previously merged, deleted, and recreated with the same name, the queue might contain a stale "completed" entry.

## Implementation Phases

### Phase 1: Add Merge Verification Functions

Create verification functions that work with all merge workflows (ff, rebase+ff, merge commit).

**File:** `lib/v0-common.sh`

```bash
# v0_verify_commit_on_branch <commit> <branch> [require_remote]
# Verify that a specific commit exists on a branch
# Returns 0 if commit is on branch, 1 if not
#
# This is the primary verification function - works for all merge workflows
# because it checks a specific commit hash, not a branch name.
#
# Args:
#   commit         - Commit hash to verify
#   branch         - Branch to check (e.g., "main", "origin/main")
#   require_remote - If "true", also verify on origin/${branch} (default: false)
v0_verify_commit_on_branch() {
  local commit="$1"
  local branch="$2"
  local require_remote="${3:-false}"

  # Validate commit exists
  if ! git cat-file -e "${commit}^{commit}" 2>/dev/null; then
    return 1  # Commit doesn't exist
  fi

  # Check if commit is ancestor of local branch
  if ! git merge-base --is-ancestor "${commit}" "${branch}" 2>/dev/null; then
    return 1
  fi

  # Optionally check remote
  if [[ "${require_remote}" = "true" ]]; then
    git fetch origin "${branch}" --quiet 2>/dev/null || true
    if ! git merge-base --is-ancestor "${commit}" "origin/${branch}" 2>/dev/null; then
      return 1
    fi
  fi

  return 0
}

# v0_verify_merge_by_op <operation> [require_remote]
# Verify merge using operation's recorded merge commit
# This is the ONLY reliable way to verify after merge completion.
#
# Works for all merge workflows because v0-merge records HEAD after do_merge():
# - Direct FF: records the branch tip (same hash)
# - Rebase+FF: records the rebased commit (new hash that's on main)
# - Merge commit: records the merge commit
#
# Args:
#   operation      - Operation name
#   require_remote - If "true", verify on origin/main (default: false)
v0_verify_merge_by_op() {
  local op="$1"
  local require_remote="${2:-false}"
  local merge_commit
  merge_commit=$(sm_read_state "${op}" "merge_commit")

  if [[ -z "${merge_commit}" ]] || [[ "${merge_commit}" = "null" ]]; then
    return 1  # No recorded merge commit
  fi

  v0_verify_commit_on_branch "${merge_commit}" "main" "${require_remote}"
}

# DEPRECATED: v0_verify_merge <branch> [require_remote]
# DO NOT USE for post-merge verification - fails for rebase workflows.
#
# This function checks if a branch's current tip is on main. It fails when:
# 1. Rebase+FF merge: original commits have different hashes than rebased commits
# 2. Post-cleanup: branch is deleted, git rev-parse fails
#
# Only valid use case: checking if a branch COULD be fast-forwarded (pre-merge).
v0_verify_merge() {
  local branch="$1"
  local require_remote="${2:-false}"

  echo "Warning: v0_verify_merge is deprecated, use v0_verify_merge_by_op" >&2

  local branch_commit
  branch_commit=$(git rev-parse "${branch}" 2>/dev/null) || return 1

  v0_verify_commit_on_branch "${branch_commit}" "main" "${require_remote}"
}
```

**Why branch-based verification fails for rebase merges:**

```
Before rebase:     After rebase+ff:      After cleanup:
main: A-B          main: A-B-C'-D'       main: A-B-C'-D'
branch: A-B-C-D    branch: A-B-C'-D'     branch: (deleted)
                   (C',D' are NEW hashes)

git merge-base --is-ancestor C main  # Returns FALSE - C is not on main, C' is
git rev-parse branch                 # FAILS - branch deleted
```

**Verification:** Unit tests in `tests/unit/v0-common.bats`

### Phase 2: Record Merge Commit in State

Modify `v0-merge` to record the actual merge commit hash before marking as merged.

**File:** `bin/v0-merge`

Update the merge success path (around line 569):

```bash
do_merge && {
  # Record the merge commit hash BEFORE cleanup
  local merge_commit
  merge_commit=$(git rev-parse HEAD)

  cleanup && git push && {
    # Verify push succeeded by checking remote
    git fetch origin main --quiet
    if git merge-base --is-ancestor "${merge_commit}" origin/main; then
      # Record merge commit in state, then update status
      sm_update_state "$(basename "${BRANCH}")" "merge_commit" "\"${merge_commit}\""
      update_operation_state && update_merge_queue_entry && {
        sm_trigger_dependents "$(basename "${BRANCH}")"
        v0_notify "${PROJECT}: merged" "${BRANCH}"
        git push origin --delete "${BRANCH}" 2>/dev/null || true
      }
    else
      echo "Error: Push succeeded but commit not found on origin/main" >&2
      exit 1
    fi
  }
}
```

**Verification:**
- Test that `merge_commit` is recorded in `state.json`
- Test that merge fails if remote verification fails

### Phase 3: Add Verification to v0-mergeq

Update `v0-mergeq` to verify merge before marking complete.

**File:** `bin/v0-mergeq`

Update `process_merge()` (around line 825):

```bash
if [[ ${merge_exit} -eq 0 ]]; then
  # Verify the merge actually happened using the recorded merge_commit
  # IMPORTANT: Do NOT use v0_verify_merge(branch) - it fails for rebase merges
  # because the original branch commits have different hashes than rebased commits,
  # and the branch is deleted after cleanup.

  # v0-merge records merge_commit in state.json before exiting 0 (Phase 2)
  # This is the actual commit on main, regardless of merge workflow used.

  # Give state file a moment to be written
  sleep 1

  if ! v0_verify_merge_by_op "${op}" "true"; then
    # Check WHY verification failed for better error messages
    local merge_commit
    merge_commit=$(sm_read_state "${op}" "merge_commit")

    if [[ -z "${merge_commit}" ]] || [[ "${merge_commit}" = "null" ]]; then
      echo "[$(date +%H:%M:%S)] Warning: v0-merge exited 0 but no merge_commit recorded"
      update_operation_state "${op}" "merge_error" '"No merge_commit in state - possible v0-merge bug"'
    else
      echo "[$(date +%H:%M:%S)] Warning: v0-merge exited 0 but commit ${merge_commit:0:8} not on origin/main"
      update_operation_state "${op}" "merge_error" "\"Commit ${merge_commit} not found on origin/main\""
    fi

    update_entry "${op}" "failed"
    update_operation_state "${op}" "merge_status" '"verification_failed"'
    return 1
  fi

  # Verified - now mark as merged
  local merged_at
  merged_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Update state.json FIRST, then queue (reverse current order)
  update_operation_state "${op}" "merge_status" '"merged"'
  update_operation_state "${op}" "merged_at" "\"${merged_at}\""
  update_operation_state "${op}" "phase" '"merged"'
  update_entry "${op}" "completed"  # Queue last
  ...
}
```

**Why we use `v0_verify_merge_by_op` instead of `v0_verify_merge`:**

| Scenario | `v0_verify_merge(branch)` | `v0_verify_merge_by_op(op)` |
|----------|---------------------------|------------------------------|
| Direct FF | ✓ Works | ✓ Works |
| Rebase+FF | ✗ FAILS (different hashes) | ✓ Works |
| Merge commit | ✓ Works | ✓ Works |
| Branch deleted | ✗ FAILS (rev-parse fails) | ✓ Works |

**Verification:** Integration test that simulates push failure

### Phase 4: Fix Status Display Priorities

Update `v0-status` to verify "merged" claims before displaying.

**File:** `bin/v0-status`

Add verification for stale/suspect merged status (around line 994):

```bash
completed)
  # Queue says completed - verify before displaying as merged
  local merge_commit
  merge_commit=$(sm_read_state "${NAME}" "merge_commit")
  if [[ -n "${merge_commit}" ]] && [[ "${merge_commit}" != "null" ]]; then
    # Has recorded commit - verify it's on main
    if v0_verify_merge_by_op "${NAME}"; then
      echo "Status: completed (merged)"
    else
      echo "Status: completed (== VERIFY FAILED ==)"
    fi
  else
    # No recorded commit - trust queue but flag as unverified
    echo "Status: completed (merged)"
  fi
  ;;
```

**Verification:** Test with mocked git states

### Phase 5: Add Staleness Detection for Queue Entries

Add check for orphaned/stale queue entries.

**File:** `bin/v0-mergeq`

Enhance `is_stale()` function (around line 430):

```bash
is_stale() {
  local op="$1"
  local state_file="${BUILD_DIR}/operations/${op}/state.json"

  # Existing: Check for merged_at
  if [[ -f "${state_file}" ]]; then
    local merged_at
    merged_at=$(jq -r '.merged_at // empty' "${state_file}")
    if [[ -n "${merged_at}" ]]; then
      # Additional: Verify the merge is real
      if v0_verify_merge_by_op "${op}"; then
        echo "already merged at ${merged_at}"
        return 0
      else
        echo "claims merged but verification failed"
        return 0  # Still stale - needs attention
      fi
    fi
  fi

  # Check if operation was recreated (queue entry older than state)
  local queue_file="${MERGEQ_DIR}/queue.json"
  if [[ -f "${queue_file}" ]] && [[ -f "${state_file}" ]]; then
    local queue_time state_time
    queue_time=$(jq -r ".entries[] | select(.operation == \"${op}\") | .queued_at // empty" "${queue_file}")
    state_time=$(jq -r '.created_at // empty' "${state_file}")
    if [[ -n "${queue_time}" ]] && [[ -n "${state_time}" ]]; then
      if [[ "${state_time}" > "${queue_time}" ]]; then
        echo "stale queue entry (operation recreated)"
        return 0
      fi
    fi
  fi

  return 1
}
```

**Verification:** Test with recreated operation scenarios

### Phase 6: Consolidate State Updates

Remove duplicate state updates by having only one source of truth.

**File:** `bin/v0-merge`

Remove the `update_merge_queue_entry()` call from `v0-merge` since `v0-mergeq` already handles this:

```bash
# In v0-merge, change line 569 from:
do_merge && cleanup && git push && update_operation_state && update_merge_queue_entry && {

# To:
do_merge && cleanup && git push && update_operation_state && {
  # Note: Queue update handled by v0-mergeq caller
```

Add a flag to indicate direct merge vs queue-driven merge:

```bash
# When called directly (not via v0-mergeq), update queue
if [[ -z "${V0_MERGEQ_CALLER:-}" ]]; then
  update_merge_queue_entry
fi
```

In `v0-mergeq`, set the flag:
```bash
V0_MERGEQ_CALLER=1 "${V0_DIR}/bin/v0-merge" "${worktree}" 2>&1
```

**Verification:** Test both direct and queue-driven merge paths

## Key Implementation Details

### Git Verification Commands

```bash
# Check if commit is ancestor of branch
git merge-base --is-ancestor <commit> <branch>

# Get current HEAD commit
git rev-parse HEAD

# Fetch latest remote state
git fetch origin main --quiet
```

### State Update Ordering

To prevent race conditions, updates should follow this order:
1. Verify merge on remote
2. Update `state.json` (all fields atomically if possible)
3. Update `queue.json` (last)

### Backward Compatibility

Operations merged before this fix won't have `merge_commit` recorded. The verification should gracefully handle this:
- If `merge_commit` exists: verify it
- If `merge_commit` is missing: trust existing status (legacy behavior)

## Failure Modes

This section documents all known failure modes and how the implementation handles them.

### FM1: Push Fails After Local Merge

**Scenario:** `do_merge` succeeds, `git push` fails (network error, auth, etc.)

**Symptom:** Local main has commits, remote doesn't. Old code might show "merged" based on local state.

**Fix:** Phase 2 verifies push succeeded before recording merge_commit:
```bash
git fetch origin main --quiet
if git merge-base --is-ancestor "${merge_commit}" origin/main; then
  # Only NOW record and mark as merged
```

### FM2: Rebase Creates New Commit Hashes

**Scenario:** Rebase+FF workflow rebases branch, creating commits C' and D' from C and D.

**Symptom:** Checking original branch tip (C) against main fails because C' is on main, not C.

**Fix:** Record `HEAD` immediately after `do_merge()` - this captures the actual commit on main (C' in this case), not the original branch tip.

### FM3: Branch Deleted Before Verification

**Scenario:** `cleanup()` deletes the branch. Later verification by branch name fails.

**Symptom:** `git rev-parse branch` fails, verification incorrectly reports failure.

**Fix:** Use `v0_verify_merge_by_op` which uses stored merge_commit hash, not branch name.

### FM4: Race Between Queue and State Updates

**Scenario:** Queue marked "completed" before state.json updated. Status reads stale state.

**Symptom:** Queue shows completed, but state.json shows old phase.

**Fix:** Phase 3 reverses update order - state.json first, queue last.

### FM5: Stale Queue Entry From Recreated Operation

**Scenario:** Op merged, deleted, recreated with same name. Old queue entry says "completed".

**Symptom:** New operation incorrectly shows as "merged".

**Fix:** Phase 5 compares queue_time vs state_time. If state is newer, queue entry is stale.

### FM6: Missing merge_commit (Legacy Operations)

**Scenario:** Operations merged before this fix don't have merge_commit recorded.

**Symptom:** Cannot verify merge, but operation was legitimately merged.

**Fix:** Graceful degradation - trust existing status for legacy ops, log for awareness.

### FM7: Concurrent Merge Attempts

**Scenario:** Two processes try to merge same branch, both see "merge succeeded".

**Symptom:** Race condition on state updates.

**Fix:** Verification checks actual git state (commit on origin/main), not just exit codes.

## Verification Plan

### Unit Tests

1. **`tests/unit/v0-common.bats`**
   - `v0_verify_commit_on_branch returns 0 for commit on branch`
   - `v0_verify_commit_on_branch returns 1 for commit not on branch`
   - `v0_verify_commit_on_branch returns 1 for nonexistent commit`
   - `v0_verify_commit_on_branch with require_remote fetches and checks origin`
   - `v0_verify_merge_by_op uses recorded merge_commit`
   - `v0_verify_merge_by_op returns 1 when merge_commit missing`
   - `v0_verify_merge_by_op works after direct ff merge`
   - `v0_verify_merge_by_op works after rebase+ff merge`
   - `v0_verify_merge_by_op works after merge commit`

2. **`tests/unit/v0-merge.bats`**
   - `merge records merge_commit in state for direct ff`
   - `merge records merge_commit in state for rebase+ff`
   - `merge records merge_commit in state for merge commit`
   - `merge fails verification if push fails`
   - `merge fails verification if commit not on origin/main after push`
   - `direct merge updates queue entry`
   - `queue-driven merge skips duplicate queue update`

3. **`tests/unit/v0-mergeq.bats`**
   - `process_merge verifies using v0_verify_merge_by_op not v0_verify_merge`
   - `process_merge detects missing merge_commit`
   - `process_merge detects commit not on origin/main`
   - `process_merge handles rebase+ff workflow correctly`
   - `is_stale detects recreated operations`
   - `state updated before queue entry`

4. **`tests/unit/v0-status.bats`**
   - `status verifies merged claims using v0_verify_merge_by_op`
   - `status shows VERIFY FAILED for unverified merges`
   - `status handles missing merge_commit gracefully (legacy)`
   - `status handles all three merge workflows`

### Integration Tests

1. **Direct FF workflow:** Create operation, ff-merge, verify status shows "merged"
2. **Rebase+FF workflow:** Create operation behind main, rebase-merge, verify status shows "merged"
3. **Merge commit workflow:** Create operation with conflicts resolved, merge-commit, verify status shows "merged"
4. **Push failure:** Create operation, simulate push failure, verify status shows error
5. **Recreated operation:** Create operation, merge, delete, recreate with same name, verify no false positive
6. **Concurrent merges:** Run concurrent merges, verify no race conditions
7. **Legacy operation:** Simulate pre-fix operation without merge_commit, verify graceful handling

### Manual Verification

```bash
# Test 1: Direct fast-forward merge
# (branch is already based on current main)
v0 feature "test-ff-merge"
# ... make changes, complete ...
v0 merge test-ff-merge
v0 status test-ff-merge  # Should show "merged"
echo "Merge type: $(git log --oneline -1 main | grep -q 'Merge' && echo 'merge commit' || echo 'fast-forward')"

# Test 2: Rebase + fast-forward merge
# (create branch, then update main, then merge - forces rebase)
v0 feature "test-rebase-merge"
# ... make changes ...
# Meanwhile, merge something else to main to force rebase
v0 merge test-rebase-merge
v0 status test-rebase-merge  # Should show "merged"

# Test 3: Check merge commit recorded for all workflows
jq '.merge_commit' .v0/build/operations/test-ff-merge/state.json
jq '.merge_commit' .v0/build/operations/test-rebase-merge/state.json

# Test 4: Verify commits are on remote
git fetch origin main
for op in test-ff-merge test-rebase-merge; do
  commit=$(jq -r '.merge_commit' .v0/build/operations/${op}/state.json)
  if git merge-base --is-ancestor "${commit}" origin/main 2>/dev/null; then
    echo "${op}: ✓ Verified on origin/main"
  else
    echo "${op}: ✗ NOT on origin/main"
  fi
done

# Test 5: Verify branch-based check would fail for rebase merge
# (demonstrates why we use commit-based verification)
for op in test-ff-merge test-rebase-merge; do
  state_file=".v0/build/operations/${op}/state.json"
  branch=$(jq -r '.branch' "${state_file}")
  if git rev-parse "${branch}" 2>/dev/null; then
    echo "${op}: branch still exists (unexpected)"
  else
    echo "${op}: branch deleted (expected) - branch-based verification would fail"
  fi
done
```
