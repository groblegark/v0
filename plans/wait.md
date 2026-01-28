# Implementation Plan: `v0 wait` Command

## Overview

Add a `v0 wait` command that blocks until an operation completes (reaches terminal phase), a bug/chore issue completes, or an optional timeout expires. This enables scripting workflows that depend on operation completion.

## Project Structure

```
bin/v0-wait                     # New command implementation
bin/v0                          # Add dispatch for 'wait' command
tests/v0-wait.bats              # Integration tests
```

## Dependencies

- No new external dependencies
- Uses existing state machine functions from `packages/state/lib/`
- Uses `wk` CLI for issue ID resolution (already a project dependency)

## Implementation Phases

### Phase 1: Create `bin/v0-wait` Command

**Goal**: Implement the core wait command with operation name support.

**File to create**: `bin/v0-wait`

```bash
#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# v0-wait - Wait for an operation to complete
set -e

V0_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${V0_DIR}/packages/cli/lib/v0-common.sh"
v0_load_config

usage() {
  v0_help <<'EOF'
Usage: v0 wait <operation> [--timeout <duration>]
       v0 wait --issue <id> [--timeout <duration>]

Wait for an operation or issue to complete.

Arguments:
  <operation>        Name of the operation to wait for

Options:
  --issue, -i <id>   Wait for operation linked to issue ID
  --timeout, -t <d>  Maximum time to wait (e.g., 30s, 5m, 1h)
  --quiet, -q        Suppress progress output
  -h, --help         Show this help

Exit codes:
  0    Operation completed successfully (merged)
  1    Operation failed or was cancelled
  2    Timeout expired
  3    Operation not found

Duration format:
  Supports suffixes: s (seconds), m (minutes), h (hours)
  Examples: 30s, 5m, 1h, 90m

Examples:
  v0 wait auth                    # Wait for 'auth' to complete
  v0 wait auth --timeout 30m      # Wait up to 30 minutes
  v0 wait --issue PROJ-123        # Wait for operation with issue ID
  v0 wait auth && echo "done"     # Chain commands on success
EOF
  exit 0
}

# Parse duration string to seconds
# Supports: 30s, 5m, 1h, or plain number (seconds)
parse_duration() {
  local duration="$1"
  local value unit

  # Extract number and optional suffix
  if [[ "${duration}" =~ ^([0-9]+)([smh])?$ ]]; then
    value="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]:-s}"

    case "${unit}" in
      s) echo "${value}" ;;
      m) echo $((value * 60)) ;;
      h) echo $((value * 3600)) ;;
    esac
  else
    echo "Error: Invalid duration format: ${duration}" >&2
    echo "Use format like: 30s, 5m, 1h" >&2
    return 1
  fi
}

# Find operation by issue ID
find_op_by_issue() {
  local issue_id="$1"

  if [[ ! -d "${BUILD_DIR}/operations" ]]; then
    return 1
  fi

  for state_file in "${BUILD_DIR}"/operations/*/state.json; do
    [[ -f "${state_file}" ]] || continue

    local epic_id
    epic_id=$(jq -r '.epic_id // empty' "${state_file}" 2>/dev/null)
    if [[ "${epic_id}" == "${issue_id}" ]]; then
      basename "$(dirname "${state_file}")"
      return 0
    fi
  done

  return 1
}

# Wait for operation to reach terminal phase
wait_for_completion() {
  local op="$1"
  local timeout_secs="$2"
  local quiet="$3"

  local start_time elapsed phase
  start_time=$(date +%s)

  while true; do
    # Check if operation exists
    if ! sm_state_exists "${op}"; then
      echo "Error: Operation '${op}' not found" >&2
      return 3
    fi

    # Get current phase
    phase=$(sm_get_phase "${op}")

    # Check for terminal state
    if sm_is_terminal_phase "${phase}"; then
      if [[ "${phase}" == "merged" ]]; then
        [[ -z "${quiet}" ]] && echo "Operation '${op}' completed successfully"
        return 0
      else
        [[ -z "${quiet}" ]] && echo "Operation '${op}' ended with phase: ${phase}"
        return 1
      fi
    fi

    # Check timeout
    if [[ -n "${timeout_secs}" ]]; then
      elapsed=$(( $(date +%s) - start_time ))
      if [[ ${elapsed} -ge ${timeout_secs} ]]; then
        [[ -z "${quiet}" ]] && echo "Timeout: Operation '${op}' still in phase '${phase}' after ${elapsed}s"
        return 2
      fi
    fi

    # Show progress (unless quiet)
    [[ -z "${quiet}" ]] && printf "\rWaiting for '%s' (phase: %s)..." "${op}" "${phase}"

    # Sleep before next check
    sleep 2
  done
}

# Parse arguments
OP_NAME=""
ISSUE_ID=""
TIMEOUT=""
QUIET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue|-i)
      ISSUE_ID="$2"
      shift 2
      ;;
    --timeout|-t)
      TIMEOUT="$2"
      shift 2
      ;;
    --quiet|-q)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Run 'v0 wait --help' for usage" >&2
      exit 1
      ;;
    *)
      OP_NAME="$1"
      shift
      ;;
  esac
done

# Resolve operation name
if [[ -n "${ISSUE_ID}" ]]; then
  OP_NAME=$(find_op_by_issue "${ISSUE_ID}")
  if [[ -z "${OP_NAME}" ]]; then
    echo "Error: No operation found for issue '${ISSUE_ID}'" >&2
    exit 3
  fi
  [[ -z "${QUIET}" ]] && echo "Found operation '${OP_NAME}' for issue '${ISSUE_ID}'"
elif [[ -z "${OP_NAME}" ]]; then
  echo "Error: Operation name or --issue required" >&2
  echo "Run 'v0 wait --help' for usage" >&2
  exit 1
fi

# Parse timeout if provided
TIMEOUT_SECS=""
if [[ -n "${TIMEOUT}" ]]; then
  TIMEOUT_SECS=$(parse_duration "${TIMEOUT}") || exit 1
fi

# Wait for completion
wait_for_completion "${OP_NAME}" "${TIMEOUT_SECS}" "${QUIET}"
```

**Verification**:
- `bin/v0-wait --help` shows usage
- ShellCheck passes: `shellcheck bin/v0-wait`

### Phase 2: Add Command Dispatch in `bin/v0`

**Goal**: Register the wait command in the main dispatcher.

**File to modify**: `bin/v0`

**Changes**:

1. Add `wait` to `PROJECT_COMMANDS` list (line 19):
```bash
PROJECT_COMMANDS="plan tree merge mergeq status build feature resume fix attach cancel stop start hold roadmap pull push archive wait"
```

2. Add dispatch case in the project-required commands section (around line 220):
```bash
  # Project-required commands
  plan|tree|merge|mergeq|status|build|fix|attach|cancel|stop|start|prune|monitor|hold|roadmap|pull|push|archive|log|wait)
```

3. Add help text (around line 90, after `hold`):
```bash
  wait          Wait for an operation to complete
```

**Verification**:
- `v0 --help` shows wait command
- `v0 wait --help` works

### Phase 3: Integration Tests

**Goal**: Add comprehensive tests for the wait command.

**File to create**: `tests/v0-wait.bats`

```bash
#!/usr/bin/env bats
# v0-wait.bats - Tests for v0-wait script

load '../packages/test-support/helpers/test_helper'

V0_WAIT="${PROJECT_ROOT}/bin/v0-wait"

setup_isolated_project() {
    local isolated_dir="${TEST_TEMP_DIR}/isolated"
    mkdir -p "${isolated_dir}/project/.v0/build/operations"
    cat > "${isolated_dir}/project/.v0.rc" <<EOF
PROJECT="testproject"
ISSUE_PREFIX="test"
EOF
    echo "${isolated_dir}/project"
}

create_isolated_operation() {
    local project_dir="$1"
    local op_name="$2"
    local json_content="$3"
    local op_dir="${project_dir}/.v0/build/operations/${op_name}"
    mkdir -p "${op_dir}"
    echo "${json_content}" > "${op_dir}/state.json"
}

setup() {
    _base_setup
}

# ============================================================================
# Help and Usage Tests
# ============================================================================

@test "v0-wait: --help shows usage" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" --help
    '
    assert_success
    assert_output --partial "Usage: v0 wait"
    assert_output --partial "Wait for an operation"
}

@test "v0-wait: requires operation name" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'"
    '
    assert_failure
    assert_output --partial "Operation name or --issue required"
}

@test "v0-wait: unknown option shows error" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" --unknown
    '
    assert_failure
    assert_output --partial "Unknown option"
}

# ============================================================================
# Immediate Completion Tests
# ============================================================================

@test "v0-wait: returns 0 for merged operation" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "merged", "machine": "testmachine"}'

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop
    '
    assert_success
    assert_output --partial "completed successfully"
}

@test "v0-wait: returns 1 for cancelled operation" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "cancelled", "machine": "testmachine"}'

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop
    '
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "ended with phase: cancelled"
}

@test "v0-wait: returns 3 for non-existent operation" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" nonexistent
    '
    assert_failure
    [ "$status" -eq 3 ]
    assert_output --partial "not found"
}

# ============================================================================
# Issue ID Tests
# ============================================================================

@test "v0-wait: finds operation by issue ID" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "merged", "machine": "testmachine", "epic_id": "TEST-123"}'

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" --issue TEST-123
    '
    assert_success
    assert_output --partial "Found operation 'testop'"
    assert_output --partial "completed successfully"
}

@test "v0-wait: returns 3 for unknown issue ID" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" --issue UNKNOWN-999
    '
    assert_failure
    [ "$status" -eq 3 ]
    assert_output --partial "No operation found for issue"
}

# ============================================================================
# Timeout Tests
# ============================================================================

@test "v0-wait: timeout returns 2 for non-terminal operation" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "executing", "machine": "testmachine"}'

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop --timeout 1s
    '
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Timeout"
}

@test "v0-wait: parses duration formats correctly" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "executing", "machine": "testmachine"}'

    # Test seconds format
    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop --timeout 1s
    '
    assert_failure
    [ "$status" -eq 2 ]

    # Test invalid format
    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop --timeout invalid
    '
    assert_failure
    assert_output --partial "Invalid duration format"
}

# ============================================================================
# Quiet Mode Tests
# ============================================================================

@test "v0-wait: --quiet suppresses progress output" {
    local project_dir
    project_dir=$(setup_isolated_project)
    create_isolated_operation "${project_dir}" "testop" '{"name": "testop", "phase": "merged", "machine": "testmachine"}'

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${V0_WAIT}"'" testop --quiet
    '
    assert_success
    assert_output ""
}

# ============================================================================
# v0 Command Integration Tests
# ============================================================================

@test "v0 wait command is routed correctly" {
    local project_dir
    project_dir=$(setup_isolated_project)

    run env -u PROJECT -u ISSUE_PREFIX -u V0_ROOT -u BUILD_DIR bash -c '
        cd "'"${project_dir}"'" || exit 1
        "'"${PROJECT_ROOT}"'/bin/v0" wait --help
    '
    assert_success
    assert_output --partial "Usage: v0 wait"
}

@test "v0 --help shows wait command" {
    run "${PROJECT_ROOT}/bin/v0" --help
    assert_success
    assert_output --partial "wait"
}
```

**Verification**:
- Run `scripts/test v0-wait` - all tests pass

### Phase 4: Documentation and Help Text

**Goal**: Add wait command to main help text in bin/v0.

**File to modify**: `bin/v0` (already covered in Phase 2)

Add to help text in `show_help()`:
```
  wait          Wait for an operation to complete
```

**Verification**:
- `v0 --help` shows wait command with description

## Key Implementation Details

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Operation completed successfully (phase: merged) |
| 1 | Operation failed or was cancelled |
| 2 | Timeout expired before completion |
| 3 | Operation not found |

### Duration Parsing

The command supports flexible duration formats:
- `30s` - 30 seconds
- `5m` - 5 minutes
- `1h` - 1 hour
- `90` - 90 seconds (plain number defaults to seconds)

### Polling Interval

The wait loop polls every 2 seconds, consistent with other v0 monitoring patterns (see `session-monitor.sh`, `conflict.sh`).

### Issue ID Resolution

When `--issue` is provided, the command searches all operation state files for a matching `epic_id` field. This is a linear scan but acceptable given typical operation counts.

### Terminal Phase Detection

Uses existing `sm_is_terminal_phase` function which returns true for:
- `merged` - operation completed successfully
- `cancelled` - operation was cancelled

## Verification Plan

1. **Lint**: Run `make lint` - ShellCheck passes on new files
2. **Unit Tests**: Run `scripts/test v0-wait` - all tests pass
3. **Integration**: Run `make check` - all lints and tests pass
4. **Manual Testing**:
   - `v0 wait --help` - shows usage
   - Create operation in executing phase, run `v0 wait op --timeout 5s` - times out with exit 2
   - Create operation in merged phase, run `v0 wait op` - exits immediately with code 0
   - Create operation in cancelled phase, run `v0 wait op` - exits with code 1
   - `v0 wait nonexistent` - exits with code 3
