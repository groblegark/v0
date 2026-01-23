# Plan: Refactor v0-merge and v0-mergeq into smaller, testable modules

**Root Feature:** `v0-25bc`

## Overview

Refactor the merge queue (`v0-mergeq`, 1191 lines) and merge command (`v0-merge`, 638 lines) into smaller, well-organized modules following the pattern established by the `lib/operations/` refactor. This improves testability, maintainability, and allows Claude to more effectively read and modify the code.

## Problem

- `bin/v0-mergeq` is 1191 lines - too large for effective maintenance and AI comprehension
- `bin/v0-merge` is 638 lines with mixed responsibilities
- Functions are defined inline in the scripts, making them hard to test in isolation
- Current tests duplicate function definitions from the scripts (brittle)
- No separation between pure business logic and I/O operations

## Goals

1. Split into smaller, focused modules (~100-300 lines each)
2. Separate **pure** (no subprocess calls) from **impure** (calls jq, git, tmux, etc.)
3. Functions become sourceable and independently testable
4. Minimize code changes - reorganize, don't rewrite
5. Tests can source modules directly instead of duplicating function definitions

## Project Structure

```
lib/
├── mergeq/
│   ├── queue.sh              # Orchestrator - sources all modules
│   ├── rules.sh              # PURE: queue entry states, priority logic
│   ├── io.sh                 # IMPURE: queue.json read/write (jq, mktemp, mv)
│   ├── locking.sh            # IMPURE: queue file locking
│   ├── daemon.sh             # IMPURE: daemon process control (start/stop)
│   ├── readiness.sh          # IMPURE: merge readiness checks (git, sm_*)
│   ├── processing.sh         # IMPURE: merge execution (process_merge, process_branch_merge)
│   ├── resolution.sh         # IMPURE: conflict resolution (tmux, claude)
│   └── display.sh            # IMPURE: status/list formatting
├── merge/
│   ├── merge.sh              # Orchestrator - sources all modules
│   ├── resolve.sh            # IMPURE: worktree/operation path resolution
│   ├── conflict.sh           # IMPURE: conflict detection and resolution launching
│   ├── execution.sh          # IMPURE: do_merge, cleanup operations
│   └── state-update.sh       # IMPURE: operation state and queue updates
└── mergeq-common.sh          # Compat shim - sources lib/mergeq/queue.sh
```

## Dependencies

- `jq` - JSON processing
- `git` - Version control operations
- `tmux` - Session management for conflict resolution
- Existing modules: `lib/v0-common.sh`, `lib/operations/state.sh`

## Implementation Phases

### Phase 1: Create lib/mergeq/ directory structure and rules module

**Goal:** Set up the module structure and move pure business logic first.

1. Create `lib/mergeq/` directory
2. Create `lib/mergeq/rules.sh` with queue constants and pure logic:
   ```bash
   # Queue entry status values
   MQ_STATUS_PENDING="pending"
   MQ_STATUS_PROCESSING="processing"
   MQ_STATUS_COMPLETED="completed"
   MQ_STATUS_FAILED="failed"
   MQ_STATUS_CONFLICT="conflict"
   MQ_STATUS_RESUMED="resumed"

   # mq_is_active_status() - Check if status is active (pending/processing)
   # mq_is_terminal_status() - Check if status is terminal
   # mq_compare_priority() - Compare two entries by priority then time
   ```
3. Create unit tests in `tests/unit/mergeq-rules.bats`

**Verification:** `make lint && make test`

### Phase 2: Extract I/O and locking modules

**Goal:** Move queue file operations to dedicated modules.

1. Create `lib/mergeq/io.sh`:
   ```bash
   mq_ensure_queue_exists()     # Create queue dir/file if missing
   mq_atomic_queue_update()     # Atomic jq update (temp + mv pattern)
   mq_read_queue()              # Read entire queue
   mq_read_entry()              # Read single entry by operation name
   mq_add_entry()               # Add new entry
   mq_update_entry_status()     # Update entry status with timestamp
   ```

2. Create `lib/mergeq/locking.sh`:
   ```bash
   mq_acquire_lock()            # Acquire queue lock with stale detection
   mq_release_lock()            # Release queue lock
   mq_with_lock()               # Execute callback with lock held (convenience)
   ```

3. Update existing tests to source modules directly instead of duplicating functions

**Verification:** `make lint && make test`

### Phase 3: Extract daemon and display modules

**Goal:** Move daemon control and display logic to dedicated modules.

1. Create `lib/mergeq/daemon.sh`:
   ```bash
   mq_daemon_running()          # Check if daemon is running
   mq_start_daemon()            # Start daemon in background
   mq_stop_daemon()             # Stop running daemon
   mq_ensure_daemon_running()   # Start if not running
   ```

2. Create `lib/mergeq/display.sh`:
   ```bash
   mq_show_status()             # Display queue status summary
   mq_list_entries()            # List all queue entries
   mq_emit_event()              # Emit event to notification hook
   ```

3. Create `lib/mergeq/queue.sh` orchestrator that sources all modules

**Verification:** `make lint && make test`

### Phase 4: Extract readiness and processing modules

**Goal:** Move merge readiness checks and processing logic.

1. Create `lib/mergeq/readiness.sh`:
   ```bash
   mq_is_stale()                # Check if entry is stale
   mq_is_branch_merge()         # Check if operation is a branch
   mq_is_branch_ready()         # Check if branch is ready to merge
   mq_is_merge_ready()          # Full readiness check
   mq_dequeue_merge()           # Get next pending operation
   mq_get_all_pending()         # Get all pending operations
   mq_get_all_conflicts()       # Get all conflict operations
   ```

2. Create `lib/mergeq/processing.sh`:
   ```bash
   mq_process_once()            # Process single merge and exit
   mq_process_watch()           # Continuous daemon loop
   mq_process_merge()           # Process operation merge
   mq_process_branch_merge()    # Process branch merge
   ```

3. Create `lib/mergeq/resolution.sh`:
   ```bash
   mq_launch_conflict_resolution()  # Launch claude for branch merge conflicts
   mq_wait_for_resolution()         # Wait for resolution session to complete
   ```

**Verification:** `make lint && make test`

### Phase 5: Extract lib/merge/ modules from v0-merge

**Goal:** Split v0-merge into reusable modules.

1. Create `lib/merge/` directory

2. Create `lib/merge/resolve.sh`:
   ```bash
   mg_resolve_operation_to_worktree()  # Resolve op name to worktree path
   mg_resolve_path_to_worktree()       # Resolve path to worktree
   mg_validate_worktree()              # Verify worktree is valid git repo
   ```

3. Create `lib/merge/conflict.sh`:
   ```bash
   mg_has_conflicts()            # Check if merge would have conflicts
   mg_worktree_has_conflicts()   # Check worktree for unresolved conflicts
   mg_commits_on_main()          # Get commits on main since merge base
   mg_commits_on_branch()        # Get commits on branch since merge base
   mg_launch_resolve_session()   # Launch claude for conflict resolution
   mg_resolve_uncommitted()      # Handle uncommitted changes
   ```

4. Create `lib/merge/execution.sh`:
   ```bash
   mg_acquire_lock()             # Acquire merge lock
   mg_release_lock()             # Release merge lock
   mg_do_merge()                 # Execute merge (ff or regular)
   mg_cleanup_worktree()         # Remove worktree, branch, tree dir
   ```

5. Create `lib/merge/state-update.sh`:
   ```bash
   mg_update_queue_entry()       # Update merge queue entry
   mg_update_operation_state()   # Update operation state to merged
   ```

**Verification:** `make lint && make test`

### Phase 6: Update bin scripts and create compat shims

**Goal:** Update bin scripts to use new modules, maintain backward compatibility.

1. Create `lib/mergeq-common.sh` compat shim:
   ```bash
   #!/bin/bash
   source "${V0_DIR}/lib/mergeq/queue.sh"
   ```

2. Update `bin/v0-mergeq`:
   - Remove inline function definitions
   - Source `lib/mergeq/queue.sh`
   - Keep only argument parsing and action dispatch
   - Target: ~100 lines

3. Update `bin/v0-merge`:
   - Remove inline function definitions
   - Source `lib/merge/merge.sh`
   - Keep only argument parsing and main flow
   - Target: ~150 lines

4. Update any other scripts that source mergeq functions

**Verification:** `make lint && make test && make check`

## Key Implementation Details

### Function Naming Convention

- Merge queue functions: `mq_` prefix (e.g., `mq_enqueue`, `mq_dequeue`)
- Merge execution functions: `mg_` prefix (e.g., `mg_do_merge`, `mg_cleanup`)
- Internal helpers: `_mq_` or `_mg_` prefix

### Module Dependencies

```
lib/mergeq/:
  Level 0 (no dependencies):
    rules.sh

  Level 1 (depends on rules):
    io.sh
    locking.sh

  Level 2 (depends on io, locking):
    daemon.sh
    display.sh
    readiness.sh

  Level 3 (depends on readiness):
    resolution.sh
    processing.sh

lib/merge/:
  Level 0:
    resolve.sh

  Level 1 (depends on resolve):
    conflict.sh
    execution.sh

  Level 2 (depends on execution):
    state-update.sh
```

### Testing Strategy

Tests can now source modules directly:

```bash
# Before (duplicating functions in test)
source_mergeq() {
    atomic_queue_update() { ... }  # Duplicated!
}

# After (sourcing module)
source_mergeq() {
    source "${PROJECT_ROOT}/lib/mergeq/io.sh"
}
```

### Backward Compatibility

- `lib/mergeq-common.sh` provides a compat shim for any external scripts
- Function names remain the same (just prefixed with `mq_` or `mg_`)
- Old function names can be aliased if needed for gradual migration

## Verification Plan

### Per-Phase Verification

After each phase:
1. `make lint` - All new files pass shellcheck
2. `make test` - All tests pass (existing and new)
3. Manual smoke test: `v0 mergeq --status`, `v0 merge --help`

### Final Verification

1. Full test suite: `make check`
2. Integration test: Create a test operation, enqueue it, verify merge works
3. Daemon test: Start daemon, add operation, verify it processes
4. Conflict test: Create conflicting changes, verify resolution flow works

### Line Count Targets

| File | Before | After |
|------|--------|-------|
| bin/v0-mergeq | 1191 | ~100 |
| bin/v0-merge | 638 | ~150 |
| lib/mergeq/*.sh | 0 | ~800 total |
| lib/merge/*.sh | 0 | ~450 total |

Total lines roughly the same, but organized into focused modules of ~100-200 lines each.
