# State Machine Refactoring Plan

**Root Feature:** `v0-9ac8`

## Overview

Refactor v0's operation state machine logic into a centralized, testable library. Currently, state transitions are scattered across `v0-feature`, `v0-mergeq`, `v0-hold`, and dynamically generated scripts (`on-complete.sh`). This makes transitions unreliable and difficult to test.

The refactoring will:
- Centralize phase transitions into a single guarded function
- Separate pure state logic (testable) from impure external calls (tmux/wk/git)
- Simplify state model: 7 phases + flags, merge status in queue file
- Optimize v0-status with batched reads

## Architecture

Two-layer design:

```
┌─────────────────────────────────────────────────────────┐
│  Commands (v0-feature, v0-mergeq, v0-hold, v0-status)   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  lib/op-lifecycle.sh (impure)                           │
│  - Calls tmux, wk, git for checks                       │
│  - Uses state-machine.sh for state changes              │
│  - Does NOT spawn processes (commands do that)          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  lib/state-machine.sh (pure)                            │
│  - Reads/writes state.json                              │
│  - Validates transitions                                │
│  - No external tool calls                               │
└─────────────────────────────────────────────────────────┘
```

**state-machine.sh** is pure: it only reads/writes JSON files. Easy to test.

**op-lifecycle.sh** is impure: it calls tmux, wk for checks. Thin layer that uses state-machine.sh for all state changes. Does not spawn processes — commands do that.

## Project Structure

```
lib/
├── state-machine.sh        # NEW: Pure state operations (no external calls)
├── op-lifecycle.sh         # NEW: Impure operations (tmux, wk checks)
├── v0-common.sh            # MODIFY: Source both new libraries
└── ...

bin/
├── v0-feature              # MODIFY: Use op-lifecycle.sh
├── v0-feature-worker       # MODIFY: Use op-lifecycle.sh
├── v0-mergeq               # MODIFY: Use op-lifecycle.sh
├── v0-status               # MODIFY: Batch reads, keep formatting here
├── v0-hold                 # MODIFY: Use op-lifecycle.sh
└── ...

tests/unit/
├── state-machine.bats      # NEW: Pure function tests (no mocking needed)
├── op-lifecycle.bats       # NEW: May need some mocking
└── ...

tests/fixtures/states/
├── init-state.json         # Existing
├── executing-state.json    # NEW
├── completed-state.json    # NEW
└── ...
```

## Dependencies

No new external dependencies. Uses existing:
- `jq` for JSON manipulation
- `bash` 3.2+ compatible constructs
- Existing bats test infrastructure

## Implementation Phases

### Phase 1: Create Pure State Machine Library

**Goal:** Create `lib/state-machine.sh` with pure functions (no external tool calls)

**Files to create:**
- `lib/state-machine.sh`
- `tests/unit/state-machine.bats`

**Key functions:**

```bash
# State file operations
sm_get_state_file()     # Get path to state file for operation
sm_read_state()         # Read a field from state
sm_update_state()       # Update state with JSON object (atomic)

# Single transition function (not one per phase)
sm_transition()         # Validate and perform transition
sm_can_transition()     # Check if transition is valid (for dry-run)

# State predicates (pure - read state.json only)
sm_is_blocked()         # Check if .after is set
sm_is_held()            # Check if .held is true
sm_is_terminal()        # Check if phase is merged/cancelled
sm_is_active()          # Inverse of is_terminal
```

**Simplified state model (7 phases, minimal flags):**

```
Phases: init → planned → queued → executing → completed → pending_merge → merged
                                            ↘ failed (resumable to earlier phases)

state.json fields:
- phase: string         # Lifecycle phase
- held: boolean         # Paused by user
- after: string|null    # Blocked waiting for another op
- failure_reason: string|null  # Why it failed (for display)

Merge-specific state lives in merge queue file (not state.json):
- queue position
- currently merging
- conflict status
```

**Data sources for v0-status (all batched):**
| Source | Provides |
|--------|----------|
| `state.json` files | phase, held, after, failure_reason |
| Merge queue file | queue position, merging status, conflict |
| `tmux list-sessions` | whether session is active |

**Transition table:**

```
From           → Allowed Transitions
───────────────────────────────────────
init           → planned, failed
planned        → queued, failed
queued         → executing, failed
executing      → completed, failed
completed      → pending_merge, failed
pending_merge  → merged, failed
merged         → (terminal)
failed         → init, planned, queued (resume)
```

**sm_update_state takes a JSON object:**
```bash
sm_update_state() {
  local op="$1" updates="$2"  # updates is JSON: {"phase": "completed", "held": false}
  local state_file=$(sm_get_state_file "$op")
  local tmp=$(mktemp)
  if jq ". + $updates" "$state_file" > "$tmp"; then
    mv "$tmp" "$state_file"
  else
    rm -f "$tmp"
    return 1
  fi
}
```

**sm_transition validates then updates:**
```bash
sm_transition() {
  local op="$1" to_phase="$2"
  sm_can_transition "$op" "$to_phase" || return 1
  sm_update_state "$op" "{\"phase\": \"$to_phase\"}"
}
```

**Verification:**
- [ ] All functions tested in `tests/unit/state-machine.bats`
- [ ] No calls to tmux, wk, git, or other external tools
- [ ] `make lint` passes
- [ ] `make test` passes

---

### Phase 2: Create Impure Lifecycle Library + Migrate Commands

**Goal:** Create `lib/op-lifecycle.sh` for operations that need external tools, then migrate commands to use both libraries.

**Files to create:**
- `lib/op-lifecycle.sh`
- `tests/unit/op-lifecycle.bats`

**Files to modify:**
- `bin/v0-feature`
- `bin/v0-feature-worker`
- `bin/v0-mergeq`
- `bin/v0-hold`

**op-lifecycle.sh functions (impure - calls external tools):**

```bash
# Merge readiness (calls tmux, wk)
op_is_merge_ready() {
  local op="$1"
  # Check phase first (cheap)
  local phase=$(sm_read_state "$op" "phase")
  [[ "$phase" == "completed" ]] || [[ "$phase" == "pending_merge" ]] || return 1

  # Check worktree exists
  local worktree=$(sm_read_state "$op" "worktree")
  [[ -d "$worktree" ]] || return 1

  # Check tmux session is gone
  ! tmux has-session -t "$op" 2>/dev/null || return 1

  # Check issues closed (calls wk)
  op_all_issues_closed "$op"
}

op_all_issues_closed() {
  local op="$1"
  local count=$(wk list --label "plan:${op}" --status todo,in_progress 2>/dev/null | wc -l)
  [[ "$count" -eq 0 ]]
}

# Dependency management (finds dependents, but does NOT spawn processes)
op_find_blocked_dependents() {
  local merged_op="$1"
  # Returns list of op names waiting on merged_op
  # Caller decides what to do with them
}

# Hold operations (uses sm_update_state)
op_set_hold() {
  local op="$1"
  sm_update_state "$op" '{"held": true}'
}

op_clear_hold() {
  local op="$1"
  sm_update_state "$op" '{"held": false}'
}
```

**Migration pattern for commands:**

```bash
# Before (in v0-feature)
update_state "phase" '"planned"'

# After
sm_transition "$NAME" "planned"
```

```bash
# Before (in v0-mergeq, inline checks)
if tmux has-session -t "$op" 2>/dev/null; then ...

# After
if op_is_merge_ready "$op"; then ...
```

**What does NOT go in libraries:**
- Process spawning (`v0-feature "$op" --resume &`) — stays in commands
- Event emission — optional, add later if needed

**Verification:**
- [ ] All commands use library functions for state changes
- [ ] `make test` passes
- [ ] Manual test: full feature cycle works

---

### Phase 3: Optimize v0-status

**Goal:** Make `v0 status` fast by batching reads. Formatting stays in v0-status.

**Files to modify:**
- `bin/v0-status`

**Batch all external reads upfront:**

```bash
# One jq call for all state files
ALL_STATES=$(jq -s 'map({name: input_filename | split("/")[-2], state: .})' \
  "${BUILD_DIR}"/operations/*/state.json 2>/dev/null || echo "[]")

# One tmux call
ACTIVE_SESSIONS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

# One read for merge queue
MERGE_QUEUE=$(cat "${MERGEQ_FILE}" 2>/dev/null || echo "[]")
```

**Query from memory:**

```bash
get_op_field() {
  local op="$1" field="$2"
  echo "$ALL_STATES" | jq -r ".[] | select(.name == \"$op\") | .state.$field"
}

is_session_active() {
  local op="$1"
  grep -qxF "$op" <<< "$ACTIVE_SESSIONS"
}

get_merge_status() {
  local op="$1"
  echo "$MERGE_QUEUE" | jq -r ".[] | select(.name == \"$op\") | .status // empty"
}
```

**Formatting stays here** — colors, icons, layout. Not in libraries.

**Verification:**
- [ ] `v0 status` renders quickly with 20+ operations
- [ ] No subprocess spawns in the display loop

## Key Implementation Details

### Atomic State Updates

State updates use temp file + mv to prevent corruption:

```bash
sm_update_state() {
  local op="$1" updates="$2"
  local state_file=$(sm_get_state_file "$op")
  local tmp=$(mktemp)
  if jq ". + $updates" "$state_file" > "$tmp"; then
    mv "$tmp" "$state_file"
  else
    rm -f "$tmp"
    return 1
  fi
}
```

### Backwards Compatibility

- Existing state.json files work without migration
- New fields (`failure_reason`) are optional, default to null
- All existing CLI commands work unchanged

### Performance Guidelines

**state-machine.sh:** Per-operation calls are fine. Transitions are infrequent.

**op-lifecycle.sh:** Short-circuit expensive checks. Check phase (cheap) before tmux/wk (expensive).

**v0-status:** Batch all external reads upfront. No subprocess spawns in display loop.

## Testing Strategy

### state-machine.bats (pure functions, no mocking)

```bash
@test "sm_can_transition allows init->planned" {
  setup_test_state "test-op" '{"phase": "init"}'
  run sm_can_transition "test-op" "planned"
  [[ "$status" -eq 0 ]]
}

@test "sm_can_transition rejects init->merged" {
  setup_test_state "test-op" '{"phase": "init"}'
  run sm_can_transition "test-op" "merged"
  [[ "$status" -eq 1 ]]
}

@test "sm_transition updates phase" {
  setup_test_state "test-op" '{"phase": "init"}'
  sm_transition "test-op" "planned"
  [[ "$(sm_read_state "test-op" "phase")" == "planned" ]]
}

@test "sm_update_state merges fields" {
  setup_test_state "test-op" '{"phase": "init", "held": false}'
  sm_update_state "test-op" '{"held": true}'
  [[ "$(sm_read_state "test-op" "held")" == "true" ]]
  [[ "$(sm_read_state "test-op" "phase")" == "init" ]]
}
```

### op-lifecycle.bats (may need mocking for tmux/wk)

```bash
@test "op_is_merge_ready returns false for wrong phase" {
  setup_test_state "test-op" '{"phase": "executing"}'
  run op_is_merge_ready "test-op"
  [[ "$status" -eq 1 ]]
}
```

### Fixtures needed

- `tests/fixtures/states/init-state.json`
- `tests/fixtures/states/executing-state.json`
- `tests/fixtures/states/completed-state.json`

## Verification Plan

### Unit Tests
```bash
make test-file FILE=tests/unit/state-machine.bats
make test-file FILE=tests/unit/op-lifecycle.bats
```

### Integration Tests (Manual)
```bash
# Full cycle
v0 feature test-sm "Test state machine" --foreground

# Hold/resume
v0 feature held-test "Test hold"
v0 hold held-test
v0 resume held-test

# Dependency
v0 feature parent "Parent"
v0 feature child "Child" --after parent
```

### Regression
```bash
make check  # lint + all tests
```
