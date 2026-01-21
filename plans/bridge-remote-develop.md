# Bridge Plan: V0_GIT_REMOTE and V0_DEVELOP_BRANCH Integration

## Overview

This plan addresses gaps discovered when reviewing commits `ccfb9cc` (V0_GIT_REMOTE) and `3133eec` (V0_DEVELOP_BRANCH) against their respective implementation plans. It ensures complete integration of both features.

## Gaps Identified

### 1. Missing from remote-config.md implementation
- `lib/hooks/stop-feature.sh:64` - Error message still has hardcoded `git push`

### 2. Interaction gaps between both features
- `bin/v0-fix:187` - Uses `origin/${V0_DEVELOP_BRANCH}` instead of `${V0_GIT_REMOTE}/${V0_DEVELOP_BRANCH}`
- `bin/v0-shutdown:232` - Remote branch listing hardcodes `origin/` pattern

## Implementation Phases

### Phase 1: Update stop-feature.sh Hook

**File:** `lib/hooks/stop-feature.sh`

**Line 64** - Update error message to include configured remote:

```bash
# Before:
echo "{\"decision\": \"block\", \"reason\": \"Uncommitted changes in worktree. Run: cd $REPO_NAME && git add . && git commit -m \\\"...\\\" && git push\"}"

# After:
echo "{\"decision\": \"block\", \"reason\": \"Uncommitted changes in worktree. Run: cd $REPO_NAME && git add . && git commit -m \\\"...\\\" && git push ${V0_GIT_REMOTE:-origin}\"}"
```

**Note:** Use fallback `${V0_GIT_REMOTE:-origin}` since hooks may run in contexts where config isn't fully loaded.

**Verification:** `grep "git push" lib/hooks/stop-feature.sh` should show V0_GIT_REMOTE.

---

### Phase 2: Fix v0-fix Remote Reference

**File:** `bin/v0-fix`

**Line 187** - Update the rev-list count to use configured remote:

```bash
# Before:
COMMITS_AHEAD=\$(git rev-list --count "origin/${V0_DEVELOP_BRANCH}..HEAD" 2>/dev/null || echo "0")

# After:
COMMITS_AHEAD=\$(git rev-list --count "${V0_GIT_REMOTE}/${V0_DEVELOP_BRANCH}..HEAD" 2>/dev/null || echo "0")
```

**Verification:** `grep -n "origin/" bin/v0-fix` should return no results.

---

### Phase 3: Fix v0-shutdown Branch Listing

**File:** `bin/v0-shutdown`

**Line 232** - Update remote branch listing pattern:

```bash
# Before:
remote_branches=$(git -C "${V0_ROOT}" branch -r --list 'origin/v0/worker/*' 2>/dev/null | sed 's/^[* ]*//' || true)

# After:
remote_branches=$(git -C "${V0_ROOT}" branch -r --list "${V0_GIT_REMOTE}/v0/worker/*" 2>/dev/null | sed 's/^[* ]*//' || true)
```

**Verification:** `grep -n "origin/v0/worker" bin/v0-shutdown` should return no results.

---

### Phase 4: Add Integration Tests

**File:** `tests/unit/v0-remote-config.bats`

Add tests to verify the combined behavior:

```bash
# ============================================================================
# Integration Tests - V0_GIT_REMOTE with V0_DEVELOP_BRANCH
# ============================================================================

@test "stop-feature.sh includes V0_GIT_REMOTE in error message" {
    local hook_file="${PROJECT_ROOT}/lib/hooks/stop-feature.sh"

    # Check that the hook uses V0_GIT_REMOTE
    run grep "V0_GIT_REMOTE" "${hook_file}"
    assert_success
}

@test "no hardcoded origin/ remote refs in bin scripts" {
    # Check that bin scripts don't have hardcoded 'origin/' in git commands
    # Exclude comments and documentation
    local scripts=(
        "${PROJECT_ROOT}/bin/v0-mergeq"
        "${PROJECT_ROOT}/bin/v0-merge"
        "${PROJECT_ROOT}/bin/v0-fix"
        "${PROJECT_ROOT}/bin/v0-chore"
        "${PROJECT_ROOT}/bin/v0-shutdown"
    )

    for script in "${scripts[@]}"; do
        # Look for origin/ followed by variable or branch pattern (not in comments)
        run bash -c "grep -n 'origin/' '$script' | grep -v '^[[:space:]]*#' | grep -v 'V0_GIT_REMOTE' || true"
        assert_output ""
    done
}
```

**Verification:** `make test-file FILE=tests/unit/v0-remote-config.bats`

---

### Phase 5: Final Verification

Run complete verification to ensure no hardcoded remote references remain:

```bash
# 1. Check for any remaining hardcoded 'origin' in git commands
grep -rn "git.*origin" bin/ lib/*.sh lib/hooks/ | \
  grep -v "V0_GIT_REMOTE" | \
  grep -v "\.bats:" | \
  grep -v "^[[:space:]]*#"

# 2. Verify lint passes
make lint

# 3. Run all tests
make test
```

## Files Summary

| File | Change | Line |
|------|--------|------|
| `lib/hooks/stop-feature.sh` | Add `${V0_GIT_REMOTE:-origin}` to error message | 64 |
| `bin/v0-fix` | Replace `origin/` with `${V0_GIT_REMOTE}/` | 187 |
| `bin/v0-shutdown` | Replace `origin/` with `${V0_GIT_REMOTE}/` | 232 |
| `tests/unit/v0-remote-config.bats` | Add integration tests | append |

## Verification Checklist

- [ ] `lib/hooks/stop-feature.sh` uses V0_GIT_REMOTE
- [ ] `bin/v0-fix` has no hardcoded `origin/` refs
- [ ] `bin/v0-shutdown` uses V0_GIT_REMOTE for branch listing
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] `grep -rn "origin/" bin/ lib/*.sh lib/hooks/ | grep -v V0_GIT_REMOTE | grep -v "#"` returns empty
