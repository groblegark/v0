# Serious Merge Queue Issues - Investigation & Fix Plan

## Overview

Despite 10+ commits attempting to fix merge queue issues (`c8784a6`, `dd2efdb`, `35dd4f2`, `93ee7b6`, `35bf5a8`, `8eb76d2`, etc.), automatic merges still fail while manual `v0 merge` commands succeed. This plan investigates the root causes and proposes fixes.

## Root Cause Analysis

### Symptoms
- Operations remain in "merging..." status indefinitely
- Manual `v0 merge <op>` works immediately
- Daemon shows "processing" but merge never completes
- Operations marked as ready but not picked up for merge

### Identified Issues

#### 1. Git Context Mismatch (HIGH PRIORITY)

**Location**: `packages/state/lib/merge-ready.sh:25-66`

The `_sm_resolve_merge_branch()` function uses `git show-ref --verify` without a `-C` flag, meaning it runs in the daemon's current working directory (the workspace), not the main repo where local branches may exist:

```bash
# Current (broken): checks refs in CWD (workspace)
if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
  _SM_RESOLVED_BRANCH="${branch}"
  return 0
fi
```

The daemon runs in `V0_WORKSPACE_DIR` (a worktree or clone), which may not have the same local branches as the main repo. When checking for `refs/remotes/${V0_GIT_REMOTE}/${candidate}`, the fetch in `processing.sh:521` only updates the workspace's refs, not the main repo's refs that might be checked elsewhere.

#### 2. Silent Fetch Failures (HIGH PRIORITY)

**Location**: `packages/mergeq/lib/processing.sh:521`

```bash
git -C "${V0_WORKSPACE_DIR}" fetch "${V0_GIT_REMOTE}" --prune 2>/dev/null || true
```

If this fetch fails (network issue, auth issue, etc.), the daemon continues with stale refs and operations appear "not ready" indefinitely. There's no logging of fetch failures.

#### 3. Unconditional `wk done` on Readiness Check (MEDIUM PRIORITY)

**Location**: `packages/state/lib/merge-ready.sh:101` and `:166`

```bash
wk done $(wk list --label "plan:${op}" -o ids 2>/dev/null) 2>/dev/null || true
```

This runs on EVERY readiness check, potentially multiple times per poll cycle. If `wk list` returns empty or fails, `wk done` is called with no arguments. This could have side effects or race conditions with the wok state.

#### 4. Verification Race Condition (MEDIUM PRIORITY)

**Location**: `packages/mergeq/lib/processing.sh:302-324`

After `v0-merge` completes, there's a 1-second sleep before verification:

```bash
sleep 1
if ! v0_verify_merge_by_op "${op}" "true"; then
```

The verification calls `git merge-base --is-ancestor "${commit}" "${V0_GIT_REMOTE}/${branch}"`, but:
1. The fetch inside `v0_verify_commit_on_branch()` (line 35 of git-verify.sh) has `2>/dev/null` which hides failures
2. If another process pushed commits between merge and verification, refs could be stale

#### 5. Environment Variable Drift (LOW PRIORITY)

**Location**: `packages/mergeq/lib/daemon.sh:74-76`

The daemon exports `V0_DEVELOP_BRANCH`, `BUILD_DIR`, `MERGEQ_DIR` at startup, but doesn't handle:
- Config changes during daemon lifetime
- Child processes that re-source `.v0.profile.rc` (which doesn't exist in workspace)

## Project Structure

```
packages/
  mergeq/lib/
    processing.sh     # Main daemon loop (needs fixes)
    readiness.sh      # Queue-level readiness (minor fixes)
  state/lib/
    merge-ready.sh    # State-level readiness (needs fixes)
  core/lib/
    git-verify.sh     # Verification functions (needs fixes)
  workspace/lib/
    validate.sh       # Workspace validation (needs logging)
```

## Dependencies

- No new external dependencies
- Uses existing: git, jq, tmux, wk

## Implementation Phases

### Phase 1: Add Diagnostic Logging

**Goal**: Understand exactly where and why merges fail in the daemon vs manual execution.

**Files to modify**:
- `packages/mergeq/lib/processing.sh`
- `packages/state/lib/merge-ready.sh`
- `packages/core/lib/git-verify.sh`

**Changes**:

1. Add logging to track fetch success/failure:
```bash
# In processing.sh, around line 521
if ! git -C "${V0_WORKSPACE_DIR}" fetch "${V0_GIT_REMOTE}" --prune 2>&1; then
    echo "[$(date +%H:%M:%S)] Warning: fetch failed, refs may be stale"
fi
```

2. Add logging to `_sm_resolve_merge_branch()`:
```bash
v0_trace "merge:readiness" "Resolving branch for ${op}: worktree=${worktree}, branch=${branch}"
v0_trace "merge:readiness" "Checking refs in: $(pwd)"
```

3. Add logging to verification:
```bash
v0_trace "merge:verify" "Verifying ${commit:0:8} on ${branch} (require_remote=${require_remote})"
```

**Verification**: Run `V0_TRACE=1 v0 mergeq --watch` and observe logs during a merge attempt.

### Phase 2: Fix Git Context Issues

**Goal**: Ensure all git operations run in the correct directory.

**Files to modify**:
- `packages/state/lib/merge-ready.sh`

**Changes**:

1. Fix `_sm_resolve_merge_branch()` to explicitly use workspace:
```bash
_sm_resolve_merge_branch() {
  local op="$1"
  local worktree="$2"
  local branch="$3"
  local git_dir="${V0_WORKSPACE_DIR:-${V0_ROOT}}"  # Explicit git context

  _SM_RESOLVED_BRANCH=""

  # If we have a valid worktree, no need to resolve branch
  if [[ -n "${worktree}" ]] && [[ "${worktree}" != "null" ]] && [[ -d "${worktree}" ]]; then
    _SM_RESOLVED_BRANCH="${branch}"
    return 0
  fi

  # No worktree - need a valid branch
  if [[ -z "${branch}" ]] || [[ "${branch}" = "null" ]]; then
    local remote="${V0_GIT_REMOTE:-origin}"
    for prefix in "feature" "fix" "chore" "bugfix" "hotfix"; do
      local candidate="${prefix}/${op}"
      # Use explicit -C flag for workspace context
      if git -C "${git_dir}" show-ref --verify --quiet "refs/remotes/${remote}/${candidate}" 2>/dev/null; then
        _SM_RESOLVED_BRANCH="${candidate}"
        return 0
      fi
    done
    return 1
  fi

  # Have branch from state - verify it exists
  if git -C "${git_dir}" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    _SM_RESOLVED_BRANCH="${branch}"
    return 0
  fi
  if git -C "${git_dir}" show-ref --verify --quiet "refs/remotes/${V0_GIT_REMOTE:-origin}/${branch}" 2>/dev/null; then
    _SM_RESOLVED_BRANCH="${branch}"
    return 0
  fi

  return 1
}
```

**Verification**: Test that operations with branches only on remote are correctly detected as ready.

### Phase 3: Fix Silent Failures & Race Conditions

**Goal**: Make failures visible and add retry logic.

**Files to modify**:
- `packages/mergeq/lib/processing.sh`
- `packages/core/lib/git-verify.sh`

**Changes**:

1. Log fetch failures and retry:
```bash
# In processing.sh mq_process_watch()
local fetch_attempts=0
while ! git -C "${V0_WORKSPACE_DIR}" fetch "${V0_GIT_REMOTE}" --prune 2>&1; do
    fetch_attempts=$((fetch_attempts + 1))
    if [[ ${fetch_attempts} -ge 3 ]]; then
        echo "[$(date +%H:%M:%S)] Warning: fetch failed after 3 attempts, refs may be stale"
        break
    fi
    sleep 2
done
```

2. Add retry logic to verification:
```bash
# In processing.sh after mq_process_merge
local verify_attempts=0
local verified=false
while [[ ${verify_attempts} -lt 3 ]] && [[ "${verified}" = false ]]; do
    sleep $((1 + verify_attempts))  # Increasing delay
    if v0_verify_merge_by_op "${op}" "true"; then
        verified=true
    else
        verify_attempts=$((verify_attempts + 1))
        git -C "${V0_WORKSPACE_DIR}" fetch "${V0_GIT_REMOTE}" "${V0_DEVELOP_BRANCH}" 2>/dev/null || true
    fi
done
```

**Verification**: Test with simulated network delays.

### Phase 4: Remove Problematic `wk done` Calls

**Goal**: Stop side effects during readiness checks.

**Files to modify**:
- `packages/state/lib/merge-ready.sh`

**Changes**:

Remove the `wk done` calls from readiness checks. These should only happen during the actual merge transition, not during polling:

```bash
# DELETE these lines from sm_is_merge_ready() and sm_merge_ready_reason()
# wk done $(wk list --label "plan:${op}" -o ids 2>/dev/null) 2>/dev/null || true
```

If issue closing is needed, move it to `sm_transition_to_merged()` in `transitions.sh`.

**Verification**: Verify `wk list` doesn't show unexpected done transitions during daemon polling.

### Phase 5: Add Workspace Health Monitoring

**Goal**: Detect and recover from workspace issues during daemon lifetime.

**Files to modify**:
- `packages/mergeq/lib/processing.sh`
- `packages/workspace/lib/validate.sh`

**Changes**:

1. Add workspace validation at start of each poll cycle:
```bash
# In mq_process_watch(), after the fetch
if ! ws_validate; then
    echo "[$(date +%H:%M:%S)] Warning: workspace invalid, attempting recovery"
    if ! ws_ensure_workspace; then
        echo "[$(date +%H:%M:%S)] Error: workspace recovery failed, sleeping"
        sleep 60
        continue
    fi
fi
```

2. Add function to detect workspace drift:
```bash
# In validate.sh
ws_check_health() {
    if ! ws_validate; then return 1; fi
    if ! ws_matches_config; then return 1; fi
    if ws_has_uncommitted_changes; then
        echo "Warning: workspace has uncommitted changes" >&2
        ws_clean_workspace
    fi
    return 0
}
```

**Verification**: Kill and restart daemon, verify workspace is validated.

### Phase 6: Comprehensive Testing

**Goal**: Ensure fixes work and don't regress.

**Tests to add/update**:
- `packages/mergeq/tests/readiness.bats` - test git context handling
- `packages/mergeq/tests/processing.bats` - test retry logic
- `tests/v0-merge.bats` - integration test for daemon merges

**Test scenarios**:
1. Merge with worktree present
2. Merge without worktree (branch only on remote)
3. Merge after network interruption
4. Merge with concurrent pushes to develop branch
5. Daemon restart during merge

## Key Implementation Details

### Git Ref Resolution Strategy

The correct order for finding a branch:
1. Check if worktree exists and is valid
2. Check `refs/remotes/${remote}/${branch}` (after fetch)
3. Check `refs/heads/${branch}` (local branch)
4. Try conventional prefixes: `feature/`, `fix/`, `chore/`, etc.

Always use explicit `-C` flag to specify git context.

### Verification Strategy

After merge completion:
1. Sleep 1s minimum (allow refs to sync)
2. Fetch from remote
3. Check `merge_commit` is ancestor of `origin/${V0_DEVELOP_BRANCH}`
4. Retry up to 3 times with increasing delays

### Logging Strategy

Use `v0_trace` with namespaces:
- `mergeq:daemon` - daemon lifecycle
- `mergeq:process` - merge execution
- `mergeq:readiness` - readiness checks
- `mergeq:verify` - merge verification

## Verification Plan

1. **Unit Tests**: `scripts/test mergeq state`
2. **Integration Tests**: `scripts/test v0-merge`
3. **Manual Testing**:
   - Start daemon, enqueue operation, watch logs
   - Verify operation transitions through: pending -> processing -> completed
   - Verify dependent operations are unblocked
4. **Regression Testing**: Run full `make check`

## Risk Assessment

| Change | Risk | Mitigation |
|--------|------|------------|
| Git context fixes | Low | Pure function changes, easy to test |
| Retry logic | Medium | Could slow down merges, add timeout limits |
| Remove wk done | Medium | Could leave issues open, test thoroughly |
| Workspace health | Low | Already exists, just adding calls |

## Success Criteria

1. Operations in "pending" status are picked up within 30 seconds
2. Merges complete without manual intervention
3. Daemon logs show clear progress through each stage
4. No false "verification_failed" after successful push
5. Dependent operations resume automatically after blocker merges
