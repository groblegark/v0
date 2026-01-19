# State Machine Refactoring Plan

**Root Feature:** `v0-9ac8`

## Overview

Refactor v0's operation state machine logic into a centralized, testable library (`lib/state-machine.sh`). Currently, state transitions are scattered across `v0-feature`, `v0-mergeq`, `v0-hold`, and dynamically generated scripts (`on-complete.sh`). This makes transitions unreliable and difficult to test.

The refactoring will:
- Centralize all phase transitions into guard-protected functions
- Make the feature→merge transition more reliable
- Improve merge queue readiness checks and error handling
- Consolidate status interpretation for consistent display
- Make hold and --after logic explicit and testable

## Project Structure

```
lib/
├── state-machine.sh        # NEW: Core state machine functions
│   ├── Phase transition guards
│   ├── State update functions
│   ├── Dependency/blocking logic
│   └── Status interpretation
├── v0-common.sh            # Existing: Add state-machine.sh sourcing
└── ...

bin/
├── v0-feature              # MODIFY: Use state-machine.sh functions
├── v0-feature-worker       # MODIFY: Use state-machine.sh functions
├── v0-mergeq               # MODIFY: Use state-machine.sh functions
├── v0-status               # MODIFY: Use consolidated status logic
├── v0-hold                 # MODIFY: Use state-machine.sh functions
└── ...

tests/unit/
├── state-machine.bats      # NEW: Comprehensive state machine tests
├── v0-feature-state.bats   # MODIFY: Update to test via library
└── ...

tests/fixtures/states/
├── init-state.json         # Existing
├── planned-state.json      # NEW: More test fixtures
├── blocked-state.json      # NEW
├── pending-merge-state.json # NEW
└── ...
```

## Dependencies

No new external dependencies. Uses existing:
- `jq` for JSON manipulation
- `bash` 3.2+ compatible constructs
- Existing bats test infrastructure

## Implementation Phases

### Phase 1: Create State Machine Library

**Goal:** Extract and centralize state transition logic into `lib/state-machine.sh`

**Files to create:**
- `lib/state-machine.sh`

**Key functions to implement:**

```bash
# State file operations
sm_get_state_file()     # Get path to state file for operation
sm_read_state()         # Read a field from state
sm_update_state()       # Update a field atomically
sm_bulk_update_state()  # Update multiple fields atomically

# Phase transition guards (return 0 if allowed, 1 if not)
sm_can_transition()     # Check if transition is valid
sm_allowed_transitions() # Return valid next phases for current phase

# Phase transitions (perform the transition with logging)
sm_transition_to_planned()
sm_transition_to_queued()
sm_transition_to_blocked()
sm_transition_to_executing()
sm_transition_to_completed()
sm_transition_to_pending_merge()
sm_transition_to_merged()
sm_transition_to_failed()

# Blocking/dependency helpers
sm_is_blocked()         # Check if operation is blocked by --after
sm_get_blocker_status() # Get status of blocking operation
sm_unblock_operation()  # Clear blocked state and resume

# Hold helpers (consolidate from v0-common.sh)
sm_is_held()            # Check if operation is held
sm_set_hold()           # Put operation on hold
sm_clear_hold()         # Release hold

# Status interpretation
sm_get_display_status() # Return user-friendly status string
sm_get_status_color()   # Return color code for status
```

**State transition table to encode:**

```
From State      → Allowed Transitions
─────────────────────────────────────────────
init           → planned, blocked, failed
planned        → queued, blocked, failed
blocked        → init, planned, queued (on unblock)
queued         → executing, blocked, failed
executing      → completed, failed, interrupted
completed      → pending_merge, merged, failed
pending_merge  → merged, conflict, failed
merged         → (terminal)
failed         → init, planned, queued (on resume)
conflict       → pending_merge (on retry), failed
interrupted    → init, planned, queued (on resume)
cancelled      → (terminal)
```

**Verification:**
- [ ] All functions have corresponding tests in `tests/unit/state-machine.bats`
- [ ] `make lint` passes
- [ ] `make test` passes

---

### Phase 2: Migrate v0-feature to Use State Machine Library

**Goal:** Replace inline state transitions in `v0-feature` with library calls

**Files to modify:**
- `bin/v0-feature`
- `bin/v0-feature-worker`

**Changes:**

1. Source the state machine library:
```bash
source "${V0_DIR}/lib/state-machine.sh"
```

2. Replace direct `update_state "phase"` calls with transition functions:
```bash
# Before (in v0-feature)
update_state "phase" '"planned"'
emit_event "plan:created" "..."

# After
sm_transition_to_planned "${NAME}" "${PLANS_DIR}/${NAME}.md"
```

3. Replace inline `on-complete.sh` generation with library call:
```bash
# The generated on-complete.sh will call:
sm_transition_to_completed "${OP_NAME}"
if sm_should_queue_merge "${OP_NAME}"; then
  sm_transition_to_pending_merge "${OP_NAME}"
  v0-mergeq --enqueue "${OP_NAME}"
fi
```

4. Replace resume/error recovery logic with library functions:
```bash
# Before
if [[ "${PHASE}" = "failed" ]]; then
  # Complex inline logic to determine resume point
fi

# After
PHASE=$(sm_get_resume_phase "${NAME}")
```

**Verification:**
- [ ] `v0 feature test --dry-run` shows expected transitions
- [ ] Existing feature state tests pass
- [ ] Manual test: `v0 feature foo "test" --foreground` completes full cycle

---

### Phase 3: Improve Merge Queue Reliability

**Goal:** Make merge queue transitions more robust with better guards and error handling

**Files to modify:**
- `bin/v0-mergeq`
- `lib/state-machine.sh` (add merge-specific functions)

**Key improvements:**

1. **Consolidate readiness checks** into state machine:
```bash
# New function in state-machine.sh
sm_is_merge_ready() {
  local op="$1"

  # Guard 1: Must be in correct state
  local phase=$(sm_read_state "${op}" "phase")
  [[ "${phase}" != "completed" ]] && [[ "${phase}" != "pending_merge" ]] && return 1

  # Guard 2: Must have worktree
  local worktree=$(sm_read_state "${op}" "worktree")
  [[ -z "${worktree}" ]] || [[ ! -d "${worktree}" ]] && return 1

  # Guard 3: tmux session must be gone
  local session=$(sm_read_state "${op}" "tmux_session")
  [[ -n "${session}" ]] && tmux has-session -t "${session}" 2>/dev/null && return 1

  # Guard 4: All issues must be closed
  sm_all_issues_closed "${op}"
}

sm_all_issues_closed() {
  local op="$1"
  local open=$(wk list --label "plan:${op}" --status todo 2>/dev/null | wc -l)
  local in_progress=$(wk list --label "plan:${op}" --status in_progress 2>/dev/null | wc -l)
  [[ "${open}" -eq 0 ]] && [[ "${in_progress}" -eq 0 ]]
}
```

2. **Add detailed failure reasons** to help debugging:
```bash
sm_merge_ready_reason() {
  local op="$1"
  # Returns human-readable reason why merge is/isn't ready
  # Used by v0-status and mergeq daemon logging
}
```

3. **Improve auto-resume logic** in mergeq watch loop:
```bash
# Move auto-resume decision to state machine
if ! sm_is_merge_ready "${op}"; then
  local reason=$(sm_merge_ready_reason "${op}")
  if [[ "${reason}" == open_issues:* ]] && ! sm_was_auto_resumed "${op}"; then
    sm_mark_auto_resumed "${op}"
    sm_transition_to_queued "${op}"  # Re-queue for execution
    v0-feature "${op}" --resume queued &
  fi
fi
```

4. **Atomic queue operations** with proper locking:
```bash
# Already has locking, but ensure transitions are atomic
sm_enqueue_for_merge() {
  local op="$1"
  sm_transition_to_pending_merge "${op}"  # Update state first
  # Then add to queue (if this fails, state is still correct)
}
```

**Verification:**
- [ ] Merge queue handles incomplete work by auto-resuming once
- [ ] Clear error messages when merge is blocked
- [ ] `v0 status --merge` shows why merges are waiting

---

### Phase 4: Consolidate Status Display Logic

**Goal:** Unify status interpretation between `v0 status`, `v0 status <name>`, and internal displays

**Files to modify:**
- `bin/v0-status`
- `lib/state-machine.sh`

**Changes:**

1. **Add status interpretation to state machine:**
```bash
# Returns: display_text|color|icon
sm_format_status() {
  local op="$1"
  local phase=$(sm_read_state "${op}" "phase")
  local merge_queued=$(sm_read_state "${op}" "merge_queued")
  local held=$(sm_read_state "${op}" "held")
  local after=$(sm_read_state "${op}" "after")

  # Determine display status
  case "${phase}" in
    init)
      if sm_has_active_session "${op}"; then
        echo "new|yellow|[planning]"
      else
        echo "new||"
      fi
      ;;
    executing)
      if sm_has_active_session "${op}"; then
        echo "assigned|cyan|[building]"
      else
        echo "assigned|cyan|"
      fi
      ;;
    completed|pending_merge)
      local merge_status=$(sm_get_merge_display_status "${op}")
      echo "completed|green|${merge_status}"
      ;;
    # ... etc
  esac
}

sm_get_merge_display_status() {
  local op="$1"
  # Check queue first (more authoritative than state.json)
  # Then fall back to state.json
  # Returns: (merged), (merging...), (== CONFLICT ==), etc.
}
```

2. **Simplify v0-status** to use library:
```bash
# Before: 100+ lines of inline status formatting
# After:
read -r display_phase status_icon merge_icon <<< $(sm_format_status_line "${op}")
printf "  %-20s %b%b%b\n" "${name}:" "${display_phase}" "${status_icon}" "${merge_icon}"
```

3. **Add "active vs past" status filtering:**
```bash
sm_is_active_operation() {
  local op="$1"
  local phase=$(sm_read_state "${op}" "phase")
  # Active: anything not in terminal state
  [[ "${phase}" != "merged" ]] && [[ "${phase}" != "cancelled" ]]
}

# In v0-status default view, only show active operations
# Add --all flag to show everything including merged
```

**Verification:**
- [ ] `v0 status` shows consistent formatting
- [ ] `v0 status <name>` matches list view for same operation
- [ ] Status colors and icons are consistent

---

### Phase 5: Refactor Hold and --after Logic

**Goal:** Make blocking/hold logic explicit and consistent

**Files to modify:**
- `bin/v0-hold`
- `bin/v0-feature` (resume handling)
- `lib/state-machine.sh`

**Changes:**

1. **Consolidate hold functions** (already in v0-common.sh, move to state-machine.sh):
```bash
sm_set_hold() {
  local op="$1"
  sm_bulk_update_state "${op}" \
    "held" "true" \
    "held_at" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  sm_emit_event "${op}" "hold:set"
}

sm_clear_hold() {
  local op="$1"
  sm_bulk_update_state "${op}" \
    "held" "false" \
    "held_at" "null"
  sm_emit_event "${op}" "hold:cleared"
}
```

2. **Explicit blocking state machine:**
```bash
sm_block_operation() {
  local op="$1"
  local blocked_by="$2"
  local resume_phase="$3"  # Phase to resume from when unblocked

  sm_bulk_update_state "${op}" \
    "phase" '"blocked"' \
    "after" "\"${blocked_by}\"" \
    "blocked_phase" "\"${resume_phase}\""
  sm_emit_event "${op}" "blocked:waiting" "Waiting for ${blocked_by}"
}

sm_unblock_operation() {
  local op="$1"
  local resume_phase=$(sm_read_state "${op}" "blocked_phase")
  [[ -z "${resume_phase}" ]] && resume_phase="init"

  sm_bulk_update_state "${op}" \
    "phase" "\"${resume_phase}\"" \
    "after" "null" \
    "blocked_phase" "null"
  sm_emit_event "${op}" "unblock:resumed"
}
```

3. **Trigger dependent operations** from state machine:
```bash
sm_trigger_dependents() {
  local merged_op="$1"
  for dep_op in $(sm_find_dependents "${merged_op}"); do
    if ! sm_is_held "${dep_op}"; then
      sm_unblock_operation "${dep_op}"
      "${V0_DIR}/bin/v0-feature" "${dep_op}" --resume &
    else
      echo "Dependent '${dep_op}' remains held"
    fi
  done
}
```

**Verification:**
- [ ] `v0 hold foo` + `v0 resume foo` works correctly
- [ ] `v0 feature bar --after foo` blocks until foo merges
- [ ] `--after --eager` plans first, then blocks
- [ ] Held operations don't auto-start when unblocked

---

### Phase 6: Add Comprehensive Tests

**Goal:** Ensure all state transitions are tested

**Files to create/modify:**
- `tests/unit/state-machine.bats` (NEW)
- `tests/fixtures/states/*.json` (NEW fixtures)

**Test categories:**

1. **Transition guard tests:**
```bash
@test "sm_can_transition allows init->planned" {
  # ...
}

@test "sm_can_transition rejects init->merged" {
  # ...
}
```

2. **Transition execution tests:**
```bash
@test "sm_transition_to_planned updates phase and plan_file" {
  # ...
}

@test "sm_transition_to_completed records completed_at timestamp" {
  # ...
}
```

3. **Blocking logic tests:**
```bash
@test "sm_block_operation sets blocked phase and after field" {
  # ...
}

@test "sm_unblock_operation restores blocked_phase" {
  # ...
}

@test "sm_trigger_dependents skips held operations" {
  # ...
}
```

4. **Merge readiness tests:**
```bash
@test "sm_is_merge_ready requires closed issues" {
  # ...
}

@test "sm_is_merge_ready requires exited tmux session" {
  # ...
}

@test "sm_merge_ready_reason returns open_issues count" {
  # ...
}
```

5. **Status display tests:**
```bash
@test "sm_format_status shows planning for active init" {
  # ...
}

@test "sm_get_merge_display_status checks queue before state" {
  # ...
}
```

**New fixtures needed:**
- `tests/fixtures/states/planned-state.json`
- `tests/fixtures/states/queued-state.json`
- `tests/fixtures/states/blocked-state.json`
- `tests/fixtures/states/completed-state.json`
- `tests/fixtures/states/pending-merge-state.json`
- `tests/fixtures/states/with-hold.json`

**Verification:**
- [ ] `make test` passes with >90% coverage of state-machine.sh
- [ ] All transition paths have at least one test
- [ ] Edge cases (missing files, invalid states) are tested

## Key Implementation Details

### Atomic State Updates

State updates must be atomic to prevent corruption:

```bash
sm_bulk_update_state() {
  local op="$1"
  shift
  local state_file=$(sm_get_state_file "${op}")
  local tmp=$(mktemp)
  local jq_filter="."

  while [[ $# -gt 0 ]]; do
    local key="$1"
    local value="$2"
    jq_filter="${jq_filter} | .${key} = ${value}"
    shift 2
  done

  if jq "${jq_filter}" "${state_file}" > "${tmp}"; then
    mv "${tmp}" "${state_file}"
  else
    rm -f "${tmp}"
    return 1
  fi
}
```

### Event Logging

All transitions should emit events for debugging:

```bash
sm_emit_event() {
  local op="$1"
  local event="$2"
  local details="${3:-}"
  local log_dir="${BUILD_DIR}/operations/${op}/logs"
  mkdir -p "${log_dir}"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${event}: ${details}" >> "${log_dir}/events.log"
}
```

### Backwards Compatibility

The refactoring must maintain backwards compatibility:
- Existing state.json files must work without migration
- All existing CLI commands must work unchanged
- Tests that create state files directly must continue to work

## Verification Plan

### Unit Tests
```bash
make test-file FILE=tests/unit/state-machine.bats
```

### Integration Tests (Manual)
1. **Full feature cycle:**
   ```bash
   v0 feature test-sm "Test state machine" --foreground
   # Should complete plan -> decompose -> execute -> merge
   ```

2. **Blocking flow:**
   ```bash
   v0 feature parent "Parent feature"
   v0 feature child "Child feature" --after parent
   # Child should block until parent merges
   ```

3. **Hold/resume flow:**
   ```bash
   v0 feature held-test "Test hold"
   v0 hold held-test
   # Should stop after current work
   v0 resume held-test
   # Should continue
   ```

4. **Merge queue flow:**
   ```bash
   v0 startup mergeq
   v0 feature merge-test "Test merge"
   # Wait for completion
   v0 status merge-test
   # Should show merged status
   ```

### Regression Tests
- All existing tests in `tests/unit/` must pass
- `make lint` must pass
- `make check` must pass
