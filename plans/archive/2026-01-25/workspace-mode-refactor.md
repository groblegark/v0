# Workspace Mode Refactor

**Goal:** Ensure no git operations ever happen in V0_ROOT (except `v0 push` and `v0 pull`). All merges and development happen in a dedicated workspace.

## Overview

Introduce `V0_WORKSPACE_MODE` configuration that determines how the dedicated workspace is created:
- **`worktree`** - Uses `git worktree add` (default for non-standard develop branches like `v0/develop`)
- **`clone`** - Uses `git clone` from V0_ROOT (default when develop branch is `main`, `develop`, or `master`)

The workspace is always checked out to `V0_DEVELOP_BRANCH` and is where all merge operations happen.

---

## Phase 1: Core Infrastructure

### 1.1 Add workspace configuration to core/lib/config.sh

- [ ] Add `V0_WORKSPACE_MODE` variable (values: `worktree`, `clone`)
- [ ] Add `V0_WORKSPACE_DIR` derived variable: `${V0_STATE_DIR}/workspace/${REPO_NAME}`
- [ ] Add `v0_infer_workspace_mode()` function:
  ```bash
  v0_infer_workspace_mode() {
    case "${V0_DEVELOP_BRANCH}" in
      main|develop|master) echo "clone" ;;
      *) echo "worktree" ;;
    esac
  }
  ```
- [ ] Update `v0_load_config()` to read `V0_WORKSPACE_MODE` from `.v0.rc`, defaulting to inferred value

### 1.2 Create new workspace package: packages/workspace/

Structure:
```
packages/workspace/
├── lib/
│   ├── workspace.sh      # Main entry point (sources all modules)
│   ├── create.sh         # Workspace creation (worktree and clone modes)
│   ├── validate.sh       # Validation and health checks
│   └── paths.sh          # Path resolution helpers
└── tests/
    ├── create.bats
    └── validate.bats
```

### 1.3 Implement workspace creation (packages/workspace/lib/create.sh)

- [ ] `ws_ensure_workspace()` - Idempotent function that creates workspace if missing
- [ ] `ws_create_worktree()` - Create workspace via `git worktree add`
- [ ] `ws_create_clone()` - Create workspace via `git clone` from V0_ROOT
- [ ] Handle worktree mode error when V0_DEVELOP_BRANCH is checked out in V0_ROOT:
  ```bash
  ws_check_branch_conflict() {
    local current_branch
    current_branch=$(git -C "${V0_ROOT}" rev-parse --abbrev-ref HEAD)
    if [[ "${current_branch}" == "${V0_DEVELOP_BRANCH}" ]]; then
      v0_error "Cannot create worktree: ${V0_DEVELOP_BRANCH} is checked out in ${V0_ROOT}"
      v0_error "Please checkout a different branch, or use V0_WORKSPACE_MODE=clone"
      return 1
    fi
  }
  ```

### 1.4 Implement workspace validation (packages/workspace/lib/validate.sh)

- [ ] `ws_validate()` - Check workspace exists and is healthy
- [ ] `ws_is_on_develop()` - Verify workspace is on V0_DEVELOP_BRANCH
- [ ] `ws_sync_to_develop()` - Reset workspace to V0_DEVELOP_BRANCH (fetch + reset)

---

## Phase 2: Update v0 init

### 2.1 Modify bin/v0 init command

- [ ] Add `V0_WORKSPACE_MODE` to generated `.v0.rc` file:
  ```bash
  # Workspace mode: 'worktree' or 'clone'
  # - worktree: uses git worktree (requires develop branch not checked out here)
  # - clone: uses local git clone (works when develop branch is checked out here)
  V0_WORKSPACE_MODE="clone"  # or "worktree" based on inference
  ```
- [ ] Call `ws_ensure_workspace()` after creating `.v0.rc`
- [ ] Update help text to explain workspace mode

---

## Phase 3: Migrate Merge Operations

### 3.1 Update packages/merge/lib/execution.sh

Replace all operations that run in MAIN_REPO with workspace:

- [ ] `mg_ensure_develop_branch()` → operate in `V0_WORKSPACE_DIR` instead of `MAIN_REPO`
- [ ] `mg_do_merge()` → run merge in workspace
- [ ] `mg_push_and_verify()` → push from workspace
- [ ] `mg_cleanup_merge()` → update to work with workspace

Key change pattern:
```bash
# Before
cd "${MAIN_REPO}"
git checkout "${V0_DEVELOP_BRANCH}"
git merge ...

# After
ws_ensure_workspace
cd "${V0_WORKSPACE_DIR}"
ws_sync_to_develop  # fetch + ensure on develop
git merge ...
```

### 3.2 Update packages/mergeq/lib/daemon.sh

- [ ] Change daemon startup to use workspace instead of MAIN_REPO:
  ```bash
  # Before
  cd "${MAIN_REPO}"

  # After
  ws_ensure_workspace
  cd "${V0_WORKSPACE_DIR}"
  ```

### 3.3 Update packages/mergeq/lib/processing.sh

- [ ] Replace `MAIN_REPO` references with `V0_WORKSPACE_DIR`
- [ ] Ensure `ws_ensure_workspace()` is called before processing
- [ ] Update `mq_process_merge()` to operate in workspace

### 3.4 Update packages/mergeq/lib/resolution.sh

- [ ] Conflict resolution sessions should run in workspace or temporary worktrees branched from workspace

### 3.5 Update bin/v0-merge

- [ ] Replace `MAIN_REPO=$(v0_find_main_repo)` with workspace usage
- [ ] Call `ws_ensure_workspace()` at start
- [ ] All git operations happen in `V0_WORKSPACE_DIR`

---

## Phase 4: Update Feature/Fix/Chore Worktrees

### 4.1 Analyze worktree parent behavior

For **worktree mode**:
- Feature worktrees are siblings to workspace (both are worktrees of V0_ROOT)
- No change needed - they already branch from V0_ROOT

For **clone mode**:
- Feature worktrees should be created from the workspace clone
- Update `bin/v0-tree` to detect clone mode and create worktrees relative to workspace

### 4.2 Update bin/v0-tree

- [ ] Add mode detection: if `V0_WORKSPACE_MODE=clone`, create worktrees from workspace
- [ ] Ensure worktrees can still be created and managed correctly in both modes

### 4.3 Update worker scripts (v0-fix, v0-chore, v0-build-worker)

- [ ] Ensure they use `v0-tree` correctly (should work if v0-tree is updated)
- [ ] Verify worktree cleanup still works

---

## Phase 5: Preserve v0 push/pull Behavior

### 5.1 Verify v0 push and v0 pull remain unchanged

These commands explicitly operate from user's current branch location in V0_ROOT. Verify they:
- [ ] Do NOT call `ws_ensure_workspace()`
- [ ] Continue to operate on user's branch in V0_ROOT
- [ ] Are the ONLY commands that perform git operations in V0_ROOT

---

## Phase 6: Migration and Compatibility

### 6.1 Auto-migration for existing projects

- [ ] When `v0_load_config()` finds no `V0_WORKSPACE_MODE` in `.v0.rc`:
  - Infer mode using `v0_infer_workspace_mode()`
  - Log info message about auto-creating workspace
- [ ] `ws_ensure_workspace()` handles first-time creation transparently

### 6.2 Add upgrade path

- [ ] `v0 init --upgrade` option to add `V0_WORKSPACE_MODE` to existing `.v0.rc`
- [ ] Or simply document that users can add it manually

---

## Phase 7: Testing

### 7.1 Unit tests for workspace package

- [ ] `packages/workspace/tests/create.bats` - Test worktree and clone creation
- [ ] `packages/workspace/tests/validate.bats` - Test validation and sync

### 7.2 Integration tests

- [ ] `tests/v0-workspace.bats` - End-to-end workspace tests
- [ ] Update `tests/v0-merge.bats` - Verify merges happen in workspace
- [ ] Update `tests/v0-mergeq.bats` - Verify queue uses workspace

### 7.3 Test matrix

| Scenario | Mode | Test |
|----------|------|------|
| New project with v0/develop | worktree | v0 init creates worktree workspace |
| New project with main | clone | v0 init creates clone workspace |
| Existing project, first merge | auto | Workspace auto-created |
| Worktree mode, develop checked out | worktree | Error with guidance |
| Clone mode, develop checked out | clone | Works fine |

---

## File Changes Summary

### New Files
- `packages/workspace/lib/workspace.sh`
- `packages/workspace/lib/create.sh`
- `packages/workspace/lib/validate.sh`
- `packages/workspace/lib/paths.sh`
- `packages/workspace/tests/create.bats`
- `packages/workspace/tests/validate.bats`
- `tests/v0-workspace.bats`

### Modified Files
- `packages/core/lib/config.sh` - Add V0_WORKSPACE_MODE, V0_WORKSPACE_DIR
- `packages/CLAUDE.md` - Add workspace to layer diagram
- `bin/v0` (init command) - Write V0_WORKSPACE_MODE to .v0.rc, create workspace
- `bin/v0-merge` - Use workspace instead of MAIN_REPO
- `bin/v0-tree` - Handle clone mode worktree creation
- `packages/merge/lib/execution.sh` - All operations in workspace
- `packages/mergeq/lib/daemon.sh` - Start daemon from workspace
- `packages/mergeq/lib/processing.sh` - Process merges in workspace
- `packages/mergeq/lib/resolution.sh` - Resolution in workspace

---

## Open Questions / Decisions Made

| Question | Decision |
|----------|----------|
| Workspace location | `${V0_STATE_DIR}/workspace/${REPO_NAME}` |
| State file location | Keep in V0_ROOT/.v0/build/ |
| Clone type | Full clone from V0_ROOT (local) |
| Branch conflict handling | Error with guidance |
| Workspace sharing | Single shared workspace per project |
| Creation timing | Eager on init + lazy fallback |
| Migration | Auto-create on first use |

---

## Rollout Plan

1. Implement Phase 1-2 (infrastructure + init)
2. Test with new projects
3. Implement Phase 3-4 (merge + worktree updates)
4. Test merge operations in workspace
5. Implement Phase 5-6 (push/pull + migration)
6. Full integration testing
7. Update documentation
