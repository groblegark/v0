# Resilient Merge: Post-Push Verification Improvements

**Root Feature:** `v0-merge` reliability

## Overview

Improve the reliability of post-push verification in `v0-merge` to handle timing issues, transient network failures, and race conditions. The current implementation fails with "Push succeeded but commit not found on origin/main" even when the push actually succeeded, because the verification step lacks retry logic and proper error handling.

## Project Structure

Key files involved:

```
bin/
  v0-merge          # Main merge script - verification logic at lines 600-627
lib/
  v0-common.sh      # v0_verify_commit_on_branch() at line 686
tests/unit/
  v0-common.bats    # Verification function tests
  v0-merge.bats     # Merge integration tests
```

## Dependencies

- `git` - For commit verification (merge-base, ls-remote, fetch)
- Existing v0 infrastructure (no new dependencies needed)

## Root Cause Analysis

The error "Push succeeded but commit not found on origin/main" occurs when:

1. **Silent fetch failure**: `git fetch origin main --quiet` fails without error handling
2. **Timing/propagation delay**: The push completed but the remote ref isn't immediately queryable
3. **Race condition**: Another merge moved origin/main forward between push and verify (though this should still pass since our commit becomes an ancestor)
4. **Stale local ref**: origin/main local ref not updated despite fetch command running

Evidence from the failed merge:
```
To github.com:alfredjeanlab/v0.git
   58040d9..4c53d52  main -> main     # Push succeeded
Error: Push succeeded but commit not found on origin/main
```

Git history shows 4c53d52 (our merge) IS an ancestor of the current HEAD (59547ef), meaning the commit exists on origin/main but verification failed.

## Implementation Phases

### Phase 1: Add Retry Logic to Verification

Create a robust verification function with retry capability.

**File:** `lib/v0-common.sh`

Add new function after `v0_verify_commit_on_branch`:

```bash
# v0_verify_push_with_retry <commit> <remote_branch> [max_attempts] [delay_seconds]
# Verify a pushed commit exists on a remote branch with retries
# Returns 0 if verified, 1 if all attempts fail
#
# Handles:
# - Transient network issues
# - Propagation delays after push
# - Git ref cache staleness
#
# Args:
#   commit        - Commit hash to verify
#   remote_branch - Remote branch (e.g., "origin/main")
#   max_attempts  - Number of verification attempts (default: 3)
#   delay_seconds - Delay between attempts (default: 2)
v0_verify_push_with_retry() {
  local commit="$1"
  local remote_branch="$2"
  local max_attempts="${3:-3}"
  local delay="${4:-2}"

  local remote="${remote_branch%%/*}"  # e.g., "origin" from "origin/main"
  local branch="${remote_branch#*/}"   # e.g., "main" from "origin/main"

  local attempt=1
  while [[ ${attempt} -le ${max_attempts} ]]; do
    # Force-refresh the remote ref
    if ! git fetch "${remote}" "${branch}" --force 2>/dev/null; then
      echo "Warning: fetch attempt ${attempt} failed" >&2
    fi

    # Try standard verification
    if git merge-base --is-ancestor "${commit}" "${remote_branch}" 2>/dev/null; then
      return 0
    fi

    # Fallback: check via ls-remote (bypasses local ref cache)
    local remote_head
    remote_head=$(git ls-remote "${remote}" "refs/heads/${branch}" 2>/dev/null | cut -f1)
    if [[ -n "${remote_head}" ]]; then
      # Check if our commit is ancestor of the remote HEAD
      if git merge-base --is-ancestor "${commit}" "${remote_head}" 2>/dev/null; then
        return 0
      fi
      # Check if commit IS the remote head
      if [[ "${commit}" = "${remote_head}"* ]] || [[ "${remote_head}" = "${commit}"* ]]; then
        return 0
      fi
    fi

    if [[ ${attempt} -lt ${max_attempts} ]]; then
      echo "Verification attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s..." >&2
      sleep "${delay}"
    fi
    ((attempt++))
  done

  return 1
}
```

**Verification:** Unit tests in `tests/unit/v0-common.bats`

### Phase 2: Add Diagnostic Information on Failure

Improve error messages to help debug verification failures.

**File:** `lib/v0-common.sh`

Add diagnostic helper:

```bash
# v0_diagnose_push_verification <commit> <remote_branch>
# Output diagnostic information when push verification fails
# Called after v0_verify_push_with_retry fails
v0_diagnose_push_verification() {
  local commit="$1"
  local remote_branch="$2"
  local remote="${remote_branch%%/*}"
  local branch="${remote_branch#*/}"

  echo "=== Push Verification Diagnostic ===" >&2
  echo "Commit to verify: ${commit}" >&2
  echo "Target branch: ${remote_branch}" >&2
  echo "" >&2

  # Check local refs
  echo "Local refs:" >&2
  echo "  HEAD: $(git rev-parse HEAD 2>/dev/null || echo 'N/A')" >&2
  echo "  main: $(git rev-parse main 2>/dev/null || echo 'N/A')" >&2
  echo "  ${remote_branch}: $(git rev-parse "${remote_branch}" 2>/dev/null || echo 'N/A')" >&2
  echo "" >&2

  # Check remote state
  echo "Remote state (via ls-remote):" >&2
  git ls-remote "${remote}" "refs/heads/${branch}" 2>/dev/null || echo "  Failed to query remote" >&2
  echo "" >&2

  # Check if commit exists at all
  if git cat-file -e "${commit}^{commit}" 2>/dev/null; then
    echo "Commit ${commit:0:8} exists locally" >&2
  else
    echo "Commit ${commit:0:8} NOT FOUND locally" >&2
  fi

  # Check ancestry
  echo "" >&2
  echo "Ancestry check:" >&2
  if git merge-base --is-ancestor "${commit}" main 2>/dev/null; then
    echo "  ${commit:0:8} IS ancestor of local main" >&2
  else
    echo "  ${commit:0:8} is NOT ancestor of local main" >&2
  fi

  echo "==================================" >&2
}
```

**Verification:** Manual testing with intentionally failed verification

### Phase 3: Update v0-merge to Use Resilient Verification

Replace the current verification logic in `v0-merge` with the new retry-capable version.

**File:** `bin/v0-merge`

Update the merge success path (around line 600-627):

Current code:
```bash
cleanup && git push && {
  # Verify push succeeded by checking remote
  git fetch origin main --quiet
  if v0_verify_commit_on_branch "${merge_commit}" "origin/main"; then
```

New code:
```bash
cleanup && git push && {
  # Verify push succeeded with retries to handle propagation delay
  if v0_verify_push_with_retry "${merge_commit}" "origin/main" 3 2; then
```

Also update the conflict resolution path (around line 561-586) similarly.

Add diagnostic output on failure:
```bash
  else
    v0_diagnose_push_verification "${merge_commit}" "origin/main"
    echo "Error: Push succeeded but commit not verified on origin/main after retries" >&2
    # Generate debug report for investigation
    "${V0_DIR}/bin/v0-debug" "${OP_NAME:-$(basename "${BRANCH}")}" 2>/dev/null || true
    exit 1
  fi
```

**Verification:** Integration test simulating delayed verification

### Phase 4: Handle Race Conditions Gracefully

When another merge moves origin/main forward during our verification, ensure we still succeed (our commit becomes an ancestor).

**File:** `lib/v0-common.sh`

The retry logic in Phase 1 already handles this by checking if our commit is an ancestor of whatever the current remote HEAD is. This phase adds explicit documentation and a test case.

**File:** `tests/unit/v0-common.bats`

```bash
@test "v0_verify_push_with_retry succeeds when remote moved forward" {
  # Setup: create commit A, "push" it, then create commit B on top
  # Verification of A should succeed because A is ancestor of B
  ...
}
```

**Verification:** Unit test for race condition scenario

### Phase 5: Add Verification Metrics/Logging

Add optional logging to track verification patterns and identify systemic issues.

**File:** `bin/v0-merge`

Add timing and attempt count logging:

```bash
local verify_start verify_end verify_duration
verify_start=$(date +%s)
if v0_verify_push_with_retry "${merge_commit}" "origin/main" 3 2; then
  verify_end=$(date +%s)
  verify_duration=$((verify_end - verify_start))
  if [[ ${verify_duration} -gt 2 ]]; then
    echo "Note: Push verification took ${verify_duration}s" >&2
  fi
```

**Verification:** Manual testing with slow network simulation

## Key Implementation Details

### Git Commands for Verification

```bash
# Primary: Check if commit is ancestor of branch
git merge-base --is-ancestor <commit> <branch>

# Fallback: Query remote ref directly (bypasses local cache)
git ls-remote origin refs/heads/main

# Force-refresh local remote ref
git fetch origin main --force

# Check commit exists
git cat-file -e <commit>^{commit}
```

### Why Retry Logic Is Needed

1. **Git propagation delay**: After `git push` returns, the remote ref may take a moment to be queryable
2. **Fetch timing**: `git fetch` may not immediately see the newly pushed commit
3. **Network transients**: Brief network issues can cause fetch to fail
4. **Ref cache**: Local git may cache the old remote ref briefly

### Backward Compatibility

- New functions are additive (no breaking changes)
- Existing `v0_verify_commit_on_branch` remains unchanged
- Only `v0-merge` callers get the improved verification

### Failure Modes Addressed

| Failure Mode | Current Behavior | New Behavior |
|--------------|------------------|--------------|
| Transient fetch failure | Immediate error | Retry 3 times |
| Propagation delay | Immediate error | Wait and retry |
| Race (remote moved forward) | May fail | Succeeds (ancestor check) |
| Persistent failure | Error, no context | Error with diagnostics |

## Verification Plan

### Unit Tests

**`tests/unit/v0-common.bats`:**

```bash
@test "v0_verify_push_with_retry returns 0 for commit on branch" {
  # Setup: commit on main
  # Verify: returns 0
}

@test "v0_verify_push_with_retry returns 1 for commit not on branch" {
  # Setup: commit on separate branch
  # Verify: returns 1 after all retries
}

@test "v0_verify_push_with_retry uses ls-remote fallback" {
  # Setup: make git fetch fail, but ls-remote work
  # Verify: returns 0 via fallback
}

@test "v0_verify_push_with_retry retries on transient failure" {
  # Setup: mock fetch to fail once then succeed
  # Verify: returns 0 after retry
}

@test "v0_verify_push_with_retry succeeds when remote moved forward" {
  # Setup: commit A exists, remote is now at B (child of A)
  # Verify: returns 0 (A is ancestor of B)
}

@test "v0_diagnose_push_verification outputs diagnostic info" {
  # Setup: any git state
  # Verify: outputs expected diagnostic sections
}
```

### Integration Tests

**`tests/unit/v0-merge.bats`:**

```bash
@test "merge succeeds with verification retry" {
  # Setup: mock slow verification
  # Verify: merge completes successfully
}

@test "merge outputs diagnostics on persistent verification failure" {
  # Setup: make verification always fail
  # Verify: diagnostic output present, debug report generated
}
```

### Manual Verification

```bash
# Test 1: Normal merge (should use 0-1 retries)
v0 feature "test-resilient-merge"
# ... make changes ...
v0 merge test-resilient-merge
# Observe: verification succeeds quickly

# Test 2: Simulate slow verification
# (Run merge while another process is pushing)
v0 feature "test-concurrent"
# ... in another terminal, push other changes rapidly ...
v0 merge test-concurrent
# Observe: may show "retrying..." but should succeed

# Test 3: Check diagnostic output
# (Disconnect network mid-merge)
v0 feature "test-offline"
# ... make changes, then disconnect network ...
v0 merge test-offline
# Observe: diagnostic output shows fetch failures and ref states

# Test 4: Verify retry count
V0_DEBUG=1 v0 merge some-branch 2>&1 | grep -i "verification\|retry"
```

## Summary

This plan addresses the "Push succeeded but commit not found on origin/main" error by:

1. Adding retry logic to handle transient failures and propagation delays
2. Using `ls-remote` as a fallback to bypass local ref caching
3. Providing diagnostic output to help debug persistent failures
4. Ensuring race conditions (remote moving forward) are handled gracefully
5. Adding timing metrics to identify systemic verification issues
