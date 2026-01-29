# Plan: Split tests/v0-status.bats

## Overview

Split `tests/v0-status.bats` (currently 1091 lines) into multiple focused test files to improve maintainability and stay under 1000 lines. Tests will be organized by logical grouping: unit tests for library functions move to the status package, while integration tests remain in `tests/`.

## Project Structure

```
packages/status/tests/
  timestamps.bats        # NEW: Unit tests for timestamps.sh functions
  blocker-display.bats   # Existing
  branch-status.bats     # Existing

tests/
  v0-status.bats         # MODIFIED: Core integration tests (~250 lines)
  v0-status-session.bats # NEW: Session detection tests (~130 lines)
  v0-status-limit.bats   # NEW: Limit and prioritization tests (~350 lines)
```

## Dependencies

- bats-core, bats-support, bats-assert (existing)
- packages/test-support/helpers/test_helper.bash (existing)

## Implementation Phases

### Phase 1: Create packages/status/tests/timestamps.bats (~180 lines)

Move timestamp utility tests to the status package unit tests:

**Tests to move:**
- `timestamp_to_epoch()` tests (lines 31-57) - 4 tests
- `format_elapsed()` tests (lines 77-121) - 8 tests
- `format_elapsed_extended()` tests (lines 147-175) - 6 tests
- `format_elapsed_with_days()` tests (lines 348-360) - 3 tests
- `get_last_updated_timestamp()` tests (lines 611-705) - 16 tests

**Pattern to follow:**
```bash
#!/usr/bin/env bats
# timestamps.bats - Unit tests for timestamp formatting functions

load '../../test-support/helpers/test_helper'

setup() {
  _base_setup
  source "${PROJECT_ROOT}/packages/status/lib/timestamps.sh"
}

@test "timestamp_to_epoch converts valid ISO8601" {
  run timestamp_to_epoch "2026-01-15T10:30:00Z"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}
```

**Note:** Remove locally-duplicated helper functions from the test file; source the library directly.

### Phase 2: Create tests/v0-status-session.bats (~130 lines)

Extract session detection tests (lines 396-514):

**Tests to move:**
- `is_session_active()` helper function
- 8 session detection tests covering:
  - Session in/not in all_sessions
  - Empty session name handling
  - Empty all_sessions handling
  - Partial match detection
  - Machine field independence (3 tests)

**Structure:**
```bash
#!/usr/bin/env bats
# Tests for v0-status session detection logic

load '../packages/test-support/helpers/test_helper'

setup() {
  _base_setup
  setup_v0_env
}

# Helper function matching v0-status session detection logic
is_session_active() {
  local session="$1"
  local all_sessions="$2"
  [[ -n "${session}" ]] && [[ "${all_sessions}" == *"${session}"* ]]
}
```

### Phase 3: Create tests/v0-status-limit.bats (~350 lines)

Extract limit and prioritization tests (lines 794-1091):

**Tests to move:**
- `create_test_operation()` helper
- `create_numbered_operations()` helper
- `should_show_worker_section()` helper
- 14 limit/pruning tests covering:
  - Default display (shows all operations)
  - `--max-ops` limiting
  - Priority ordering (open > blocked > completed)
  - Summary line for pruned operations
  - `priority_class` classification
- 4 short mode visibility tests

**Structure:**
```bash
#!/usr/bin/env bats
# Tests for v0-status --max-ops and operation prioritization

load '../packages/test-support/helpers/test_helper'

setup() {
  _base_setup
  setup_v0_env
}

# Helper: create a test operation with given phase
create_test_operation() {
  local name="$1"
  local phase="$2"
  # ...
}
```

### Phase 4: Update tests/v0-status.bats (~250 lines)

Keep core integration tests:

**Tests to keep:**
- Status display tests (lines 181-227) - 3 tests
- Queue status display tests (lines 233-261) - 2 tests
- Prune deprecation tests (lines 267-325) - 4 tests
- Recently Completed Section tests (lines 363-393) - 2 tests
- State machine integration tests (lines 520-552) - 5 tests
- Last-updated timestamp integration tests (lines 711-792) - 5 tests

**Remove from file:**
- All locally-defined helper functions that duplicate library code
- Tests moved to other files

**Final structure:**
```bash
#!/usr/bin/env bats
# Tests for v0-status - Integration tests for the status command

load '../packages/test-support/helpers/test_helper'

setup() {
  _base_setup
  setup_v0_env
}

# ============================================================================
# Status display tests
# ============================================================================

@test "status formatting handles empty operations directory" { ... }

# ============================================================================
# Queue status display tests
# ============================================================================

# ============================================================================
# Prune deprecation tests
# ============================================================================

# ============================================================================
# Recently Completed Section tests
# ============================================================================

# ============================================================================
# State machine integration tests
# ============================================================================

# ============================================================================
# Last-updated timestamp integration tests
# ============================================================================
```

### Phase 5: Verification

1. Run all new test files individually:
   ```bash
   scripts/test status            # Package unit tests
   scripts/test v0-status         # Main integration tests
   scripts/test v0-status-session # Session tests
   scripts/test v0-status-limit   # Limit tests
   ```

2. Verify line counts:
   ```bash
   wc -l tests/v0-status*.bats packages/status/tests/*.bats
   ```

3. Run full test suite:
   ```bash
   make check
   ```

## Key Implementation Details

### Test Isolation Pattern

Each new test file follows the project pattern:
- Load `test_helper` for base setup
- Call `_base_setup` and `setup_v0_env` in setup()
- Use `$BUILD_DIR`, `$PROJECT_ROOT` from test helper
- All temp files in `$TEST_TEMP_DIR`

### Helper Function Placement

| Function | Location |
|----------|----------|
| `timestamp_to_epoch()` | Source from `packages/status/lib/timestamps.sh` |
| `format_elapsed()` | Source from `packages/status/lib/timestamps.sh` |
| `get_last_updated_timestamp()` | Source from `packages/status/lib/timestamps.sh` |
| `is_session_active()` | Define locally in `v0-status-session.bats` |
| `create_test_operation()` | Define locally in `v0-status-limit.bats` |
| `create_numbered_operations()` | Define locally in `v0-status-limit.bats` |
| `should_show_worker_section()` | Define locally in `v0-status-limit.bats` |

### Cross-Platform Considerations

The `format_elapsed_extended()` function in tests uses different format than the library's `format_elapsed()`. Keep the extended tests in `packages/status/tests/timestamps.bats` but test them as local helpers since they document alternative formatting that could be useful.

## Verification Plan

1. **Pre-split baseline:**
   ```bash
   scripts/test v0-status  # Verify all tests pass
   ```

2. **After each phase:**
   - Run `scripts/test` for affected files
   - Verify no duplicate test names

3. **Final verification:**
   ```bash
   make check                           # Full lint + test
   wc -l tests/v0-status.bats          # Must be < 1000
   scripts/test v0-status v0-status-session v0-status-limit status
   ```

4. **Coverage check:**
   - Grep for `@test` in old file: `grep -c '@test' tests/v0-status.bats` (before)
   - Sum of `@test` in all new files should equal original count

**Expected line counts after split:**
- `tests/v0-status.bats`: ~250 lines
- `tests/v0-status-session.bats`: ~130 lines
- `tests/v0-status-limit.bats`: ~350 lines
- `packages/status/tests/timestamps.bats`: ~280 lines
