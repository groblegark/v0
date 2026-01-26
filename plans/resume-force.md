# Implementation Plan: Resume --force Flag

## Overview

Add a `--force` flag to `v0 resume` that allows bypassing blockers. Currently, when resuming a blocked operation, it shows a message and exits silently with status 0. This change will:

1. Exit with non-zero status when blocked (instead of silent success)
2. Show a clear warning message about the blocker
3. Allow users to bypass blockers with `v0 resume --force`

## Project Structure

Files to modify:
```
bin/v0              # Pass --force to v0-build
bin/v0-build        # Add --force flag handling, change exit behavior
```

## Dependencies

None - uses existing wok integration for blocker detection.

## Implementation Phases

### Phase 1: Add --force flag to v0-build

**File:** `bin/v0-build`

1. Add `FORCE=false` variable near other flag declarations (~line 20)
2. Add `--force|-f)` case to argument parsing (~line 43):
   ```bash
   --force|-f)
     FORCE=true
     shift
     ;;
   ```

3. Modify the blocker check block (~lines 427-440) to:
   - If blocked and NOT force: show error, exit 1
   - If blocked and force: show warning, continue execution

```bash
EPIC_ID=$(get_state epic_id)
if [[ -n "${EPIC_ID}" ]] && [[ "${EPIC_ID}" != "null" ]]; then
  FIRST_BLOCKER=$(v0_get_first_open_blocker "${EPIC_ID}")
  if [[ -n "${FIRST_BLOCKER}" ]]; then
    BLOCKER_NAME=$(v0_blocker_to_op_name "${FIRST_BLOCKER}")
    if [[ "${FORCE}" == "true" ]]; then
      warn "Ignoring blocker '${BLOCKER_NAME}' (--force)"
    else
      error "Operation is blocked by '${BLOCKER_NAME}'"
      echo ""
      echo "To resume anyway, use:"
      echo "  v0 resume --force ${NAME}"
      echo ""
      echo "To remove the blocker, either:"
      echo "  - Complete the blocking operation"
      echo "  - Remove the dependency: wk undep ${EPIC_ID} blocked-by ${FIRST_BLOCKER}"
      exit 1
    fi
  fi
fi
```

### Phase 2: Pass --force from v0 resume alias

**File:** `bin/v0` (~line 236)

The current alias:
```bash
resume)
  exec "${V0_DIR}/bin/v0-build" --resume "$@"
  ;;
```

No change needed - `"$@"` already passes all arguments including `--force`.

### Phase 3: Add integration test

**File:** `tests/v0-resume-force.bats` (new file)

```bash
#!/usr/bin/env bats

load test-support/helpers

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

@test "v0 resume shows error when blocked" {
  # Create a blocked operation
  create_blocked_operation "test-op" "blocker-op"

  # Resume should fail with exit 1
  run v0 resume test-op
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked by"* ]]
  [[ "$output" == *"--force"* ]]
}

@test "v0 resume --force bypasses blocker" {
  # Create a blocked operation
  create_blocked_operation "test-op" "blocker-op"

  # Resume with --force should proceed
  run v0 resume --force test-op
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ignoring blocker"* ]] || [[ "$output" == *"Resuming"* ]]
}
```

## Key Implementation Details

### Exit Code Change

The main behavior change is in exit codes:
- **Before:** Exit 0 when blocked (silent success)
- **After:** Exit 1 when blocked (failure), exit 0 when `--force` is used

### Message Types

Use existing logging functions from `packages/core/lib/logging.sh`:
- `error "..."` - For the blocked error message
- `warn "..."` - For the force bypass warning

### Worker-Level Blocking

The worker (`bin/v0-build-worker`) has its own blocker check in `check_wok_blockers()` (~line 216). This function:
- Returns 1 when blocked (pauses worker)
- Emits `blocked:paused` event

This does NOT need `--force` support - the worker should respect blockers. The `--force` flag only applies to the initial resume command, allowing the worker to start. If the worker later hits a blocker during execution, it will pause as designed.

## Verification Plan

1. **Unit verification:**
   - Run `scripts/test v0-resume-force` after creating the test file

2. **Manual verification:**
   ```bash
   # Create two operations where op2 depends on op1
   v0 start op1 "First operation"
   v0 start op2 "Second operation" --after op1

   # Try resuming op2 (should fail with exit 1)
   v0 resume op2
   echo "Exit code: $?"  # Should be 1

   # Force resume op2 (should succeed with warning)
   v0 resume --force op2
   echo "Exit code: $?"  # Should be 0
   ```

3. **Lint check:**
   ```bash
   make lint
   ```

4. **Full test suite:**
   ```bash
   make check
   ```
