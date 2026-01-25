# Workspace Mode Review & Validation

**Prerequisite:** Complete `workspace-mode-refactor.md`

**Goal:** Verify the workspace mode implementation is complete, tested, documented, and adheres to the spec.

---

## Phase 1: Spec Compliance Audit

### 1.1 Core requirement: No git operations in V0_ROOT

- [ ] Audit all files in `packages/merge/lib/` for any `cd "${V0_ROOT}"` or `cd "${MAIN_REPO}"`
- [ ] Audit all files in `packages/mergeq/lib/` for any V0_ROOT git operations
- [ ] Audit `bin/v0-merge` for any V0_ROOT git operations
- [ ] Audit `bin/v0-build-worker` for any V0_ROOT git operations
- [ ] Grep entire codebase for `MAIN_REPO` usage - should only appear in:
  - `v0_find_main_repo()` definition
  - `v0 push` / `v0 pull` (allowed)
  - Comments/docs
- [ ] Grep for `cd.*V0_ROOT` patterns - should only appear in push/pull

### 1.2 Workspace mode inference

- [ ] Verify `v0 init` with `V0_DEVELOP_BRANCH=main` → writes `V0_WORKSPACE_MODE="clone"`
- [ ] Verify `v0 init` with `V0_DEVELOP_BRANCH=develop` → writes `V0_WORKSPACE_MODE="clone"`
- [ ] Verify `v0 init` with `V0_DEVELOP_BRANCH=master` → writes `V0_WORKSPACE_MODE="clone"`
- [ ] Verify `v0 init` with `V0_DEVELOP_BRANCH=v0/develop` → writes `V0_WORKSPACE_MODE="worktree"`
- [ ] Verify `v0 init` with `V0_DEVELOP_BRANCH=agent` → writes `V0_WORKSPACE_MODE="worktree"`

### 1.3 Workspace creation behavior

- [ ] Verify eager creation: `v0 init` creates workspace immediately
- [ ] Verify lazy creation: running `v0 merge` without workspace auto-creates it
- [ ] Verify lazy creation: running `v0 mergeq --watch` without workspace auto-creates it
- [ ] Verify idempotency: calling `ws_ensure_workspace()` twice is safe

### 1.4 Error handling

- [ ] Verify worktree mode with develop checked out in V0_ROOT produces clear error
- [ ] Verify error message includes guidance to checkout different branch or use clone mode
- [ ] Verify clone mode works regardless of what's checked out in V0_ROOT

### 1.5 v0 push/pull exemption

- [ ] Verify `v0 push` still operates in V0_ROOT (user's branch)
- [ ] Verify `v0 pull` still operates in V0_ROOT (user's branch)
- [ ] Verify neither command calls `ws_ensure_workspace()`

---

## Phase 2: Test Coverage Audit

### 2.1 Review workspace package tests

- [ ] `packages/workspace/tests/create.bats` exists and covers:
  - Worktree mode creation
  - Clone mode creation
  - Idempotent re-creation
  - Branch conflict detection (worktree mode)
- [ ] `packages/workspace/tests/validate.bats` exists and covers:
  - Workspace health check
  - Sync to develop branch
  - Detection of corrupted/missing workspace

### 2.2 Review integration tests

- [ ] `tests/v0-workspace.bats` exists with end-to-end scenarios
- [ ] `tests/v0-merge.bats` updated to verify merge happens in workspace
- [ ] `tests/v0-mergeq.bats` updated to verify queue daemon uses workspace

### 2.3 Run full test suite

- [ ] `make check` passes
- [ ] `scripts/test workspace` passes
- [ ] `scripts/test v0-merge` passes
- [ ] `scripts/test v0-mergeq` passes

### 2.4 Manual smoke tests

| Test | Mode | Steps | Expected |
|------|------|-------|----------|
| Fresh init (clone) | clone | `v0 init` with main branch | Workspace created as clone |
| Fresh init (worktree) | worktree | `v0 init` with v0/develop | Workspace created as worktree |
| Merge operation | both | `v0 build` → complete → merge | Merge happens in workspace |
| Conflict resolution | both | Create conflicting changes | Resolution session in workspace |
| Push/pull | both | `v0 push`, `v0 pull` | Operations in V0_ROOT |

---

## Phase 3: Edge Case Verification

### 3.1 Workspace corruption recovery

- [ ] Delete workspace directory, run `v0 merge` → should recreate
- [ ] Corrupt workspace git state, run command → should detect and guide user
- [ ] Workspace on wrong branch, run merge → should sync to develop first

### 3.2 Mode switching

- [ ] Change `V0_WORKSPACE_MODE` in `.v0.rc` from worktree to clone:
  - What happens to existing worktree workspace?
  - Does new clone workspace get created?
  - Document expected behavior
- [ ] Change from clone to worktree:
  - What happens to existing clone workspace?
  - Document expected behavior

### 3.3 Concurrent operations

- [ ] Two merges queued simultaneously → workspace handles sequentially
- [ ] Daemon running + manual `v0 merge` → proper locking/coordination

### 3.4 Network scenarios (clone mode)

- [ ] Clone workspace can push to remote
- [ ] Clone workspace can fetch from remote
- [ ] Verify remote is configured correctly (origin pointing to same as V0_ROOT's origin)

---

## Phase 4: Documentation Review

### 4.1 Update CLAUDE.md

- [ ] Add `packages/workspace/` to directory structure
- [ ] Update package layers (workspace is Layer 1, alongside state/mergeq)
- [ ] Document `V0_WORKSPACE_MODE` in configuration section

### 4.2 Update packages/CLAUDE.md

- [ ] Add workspace package to layer diagram
- [ ] Document workspace package dependencies

### 4.3 Review/update inline documentation

- [ ] `packages/workspace/lib/*.sh` have clear function docstrings
- [ ] `packages/core/lib/config.sh` documents new variables
- [ ] `.v0.rc` template includes explanatory comments for `V0_WORKSPACE_MODE`

### 4.4 Update help text

- [ ] `v0 --help` mentions workspace mode if relevant
- [ ] `v0 init --help` explains workspace mode options
- [ ] Error messages include actionable guidance

### 4.5 Check for stale documentation

- [ ] Search docs for "MAIN_REPO" references - update or remove
- [ ] Search for documentation mentioning "main checkout" or "main repo" for merges
- [ ] Update any diagrams showing merge flow

---

## Phase 5: Code Quality Review

### 5.1 Consistency check

- [ ] All workspace functions use `ws_` prefix
- [ ] Error messages follow existing style (use `v0_error`, `v0_warn`)
- [ ] Logging follows existing patterns

### 5.2 Unused code cleanup

- [ ] `v0_find_main_repo()` - is it still needed? Where?
- [ ] Remove any dead code paths that referenced MAIN_REPO for merges
- [ ] Check for commented-out old implementation

### 5.3 ShellCheck compliance

- [ ] `make lint` passes with no new warnings
- [ ] New workspace package files pass ShellCheck

### 5.4 Dependency layering

- [ ] Verify workspace package only depends on Layer 0 (core)
- [ ] Verify no circular dependencies introduced
- [ ] Update `packages/CLAUDE.md` layer diagram if needed

---

## Phase 6: Migration Path Verification

### 6.1 Existing project upgrade

- [ ] Take existing project without `V0_WORKSPACE_MODE` in `.v0.rc`
- [ ] Run `v0 status` or `v0 merge` → workspace auto-created
- [ ] Verify inferred mode matches develop branch
- [ ] Verify no data loss or state corruption

### 6.2 Mixed state handling

- [ ] Project with old merge queue entries → still processable
- [ ] Project with in-progress operations → can complete
- [ ] Project with pending merges → queue drains correctly

---

## Phase 7: Final Checklist

### 7.1 Acceptance criteria

- [ ] `grep -r "cd.*MAIN_REPO" packages/merge packages/mergeq bin/v0-merge` returns nothing (except push/pull)
- [ ] All merges demonstrably happen in `${V0_STATE_DIR}/workspace/`
- [ ] `v0 push` and `v0 pull` still work from user's V0_ROOT checkout
- [ ] New projects get workspace created on init
- [ ] Existing projects get workspace created on first operation
- [ ] Test suite passes: `make check`

### 7.2 Sign-off items

- [ ] Code reviewed for spec compliance
- [ ] Tests reviewed for coverage
- [ ] Documentation updated
- [ ] Manual smoke tests passed
- [ ] No regressions in existing functionality

---

## Appendix: Grep Commands for Audit

```bash
# Find any remaining MAIN_REPO usage (should only be in push/pull and definition)
grep -rn "MAIN_REPO" packages/ bin/ --include="*.sh"

# Find cd to V0_ROOT (should only be in push/pull)
grep -rn 'cd.*V0_ROOT' packages/ bin/ --include="*.sh"
grep -rn 'cd "\${V0_ROOT}"' packages/ bin/ --include="*.sh"

# Find git operations - verify they're in workspace context
grep -rn "git checkout" packages/merge packages/mergeq --include="*.sh"
grep -rn "git merge" packages/merge packages/mergeq --include="*.sh"
grep -rn "git push" packages/merge packages/mergeq --include="*.sh"

# Verify workspace functions exist
grep -rn "ws_ensure_workspace" packages/ bin/ --include="*.sh"
grep -rn "ws_create_" packages/workspace --include="*.sh"
grep -rn "ws_validate" packages/workspace --include="*.sh"
```
