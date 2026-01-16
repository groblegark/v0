#!/usr/bin/env bash
# test_helper.bash - Common setup/teardown for BATS tests
#
# Usage: load 'helpers/test_helper'

# Get the tests directory path
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Track the original working directory to ensure test isolation
export ORIGINAL_PWD="${PWD}"

# Determine BATS library path
if [[ -n "${BATS_LIB_PATH:-}" ]]; then
    _BATS_LIB="${BATS_LIB_PATH}"
elif [[ -d "${TESTS_DIR}/bats/bats-support" ]]; then
    _BATS_LIB="${TESTS_DIR}/bats"
else
    # System installation (Homebrew on macOS, apt on Linux)
    _BATS_LIB="/usr/local/lib"
fi

# Load BATS helper libraries
load "${_BATS_LIB}/bats-support/load.bash"
load "${_BATS_LIB}/bats-assert/load.bash"

# Create isolated test environment
setup() {
    # Create unique temp directory for each test
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Create minimal project structure
    mkdir -p "$TEST_TEMP_DIR/project"
    mkdir -p "$TEST_TEMP_DIR/project/.v0/build/operations"
    mkdir -p "$TEST_TEMP_DIR/state"

    # Set up mock home directory
    export REAL_HOME="$HOME"
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME/.local/state/v0"

    # Enable test mode to disable notifications and enable test safeguards
    export V0_TEST_MODE=1
    export V0_NO_NOTIFICATIONS=1  # Additional safety for notification suppression

    # Clear v0 state variables to ensure test isolation
    # This prevents tests from accidentally using the real project's config
    unset V0_ROOT
    unset PROJECT
    unset ISSUE_PREFIX
    unset BUILD_DIR
    unset PLANS_DIR
    unset V0_STATE_DIR

    # Ensure we start in the project directory
    cd "$TEST_TEMP_DIR/project"

    # Track original PATH
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    # Restore HOME
    export HOME="$REAL_HOME"

    # Restore PATH
    export PATH="$ORIGINAL_PATH"

    # Clean up temp directory
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Source a library file from lib/
# Usage: source_lib "v0-common.sh"
source_lib() {
    local lib="$1"
    source "$PROJECT_ROOT/lib/$lib"
}

# Source library with mocks enabled
# Usage: source_lib_with_mocks "v0-common.sh"
source_lib_with_mocks() {
    local lib="$1"
    # Add mock-bin to PATH before sourcing
    export PATH="$TESTS_DIR/helpers/mock-bin:$PATH"
    source "$PROJECT_ROOT/lib/$lib"
}

# Create a minimal .v0.rc configuration file
# Usage: create_v0rc [project_name] [issue_prefix]
create_v0rc() {
    local project="${1:-testproject}"
    local prefix="${2:-test}"
    cat > "$TEST_TEMP_DIR/project/.v0.rc" <<EOF
PROJECT="$project"
ISSUE_PREFIX="$prefix"
EOF
}

# Create a .v0.rc with custom content
# Usage: create_v0rc_content "content"
create_v0rc_content() {
    echo "$1" > "$TEST_TEMP_DIR/project/.v0.rc"
}

# Create a state.json file for an operation
# Usage: create_operation_state "operation-name" '{"name": "op", "phase": "init"}'
create_operation_state() {
    local op_name="$1"
    local json_content="$2"
    local op_dir="$TEST_TEMP_DIR/project/.v0/build/operations/$op_name"
    mkdir -p "$op_dir"
    echo "$json_content" > "$op_dir/state.json"
}

# Create a queue.json file
# Usage: create_queue_file '{"version": 1, "entries": []}'
create_queue_file() {
    local json_content="$1"
    local queue_dir="$TEST_TEMP_DIR/project/.v0/build/mergeq"
    mkdir -p "$queue_dir/logs"
    echo "$json_content" > "$queue_dir/queue.json"
}

# Copy a fixture file to the test temp directory
# Usage: use_fixture "queues/multi-priority.json" "queue.json"
use_fixture() {
    local fixture="$1"
    local dest="$2"
    cp "$TESTS_DIR/fixtures/$fixture" "$TEST_TEMP_DIR/$dest"
}

# Assert that a file exists
# Usage: assert_file_exists "$path"
assert_file_exists() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Expected file to exist: $path" >&2
        return 1
    fi
}

# Assert that a file does not exist
# Usage: assert_file_not_exists "$path"
assert_file_not_exists() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "Expected file to not exist: $path" >&2
        return 1
    fi
}

# Assert that a directory exists
# Usage: assert_dir_exists "$path"
assert_dir_exists() {
    local path="$1"
    if [ ! -d "$path" ]; then
        echo "Expected directory to exist: $path" >&2
        return 1
    fi
}

# Assert JSON field equals value
# Usage: assert_json_field "file.json" ".field" "expected"
assert_json_field() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual=$(jq -r "$field" "$file")
    if [ "$actual" != "$expected" ]; then
        echo "JSON field $field: expected '$expected', got '$actual'" >&2
        return 1
    fi
}

# Get JSON field value
# Usage: value=$(get_json_field "file.json" ".field")
get_json_field() {
    local file="$1"
    local field="$2"
    jq -r "$field" "$file"
}

# Create a mock git repository
# Usage: init_mock_git_repo [path]
init_mock_git_repo() {
    local path="${1:-$TEST_TEMP_DIR/project}"
    (
        cd "$path"
        git init --quiet
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "test" > README.md
        git add README.md
        git commit --quiet -m "Initial commit"
    )
}

# Create a branch in the mock git repo
# Usage: create_git_branch "branch-name" [path]
create_git_branch() {
    local branch="$1"
    local path="${2:-$TEST_TEMP_DIR/project}"
    (
        cd "$path"
        git checkout -b "$branch" --quiet 2>/dev/null || git checkout "$branch" --quiet
    )
}

# Freeze the date for reproducible tests
# Usage: freeze_date "2026-01-15T10:00:00Z"
freeze_date() {
    local frozen_date="$1"
    export MOCK_DATE="$frozen_date"
}

# ============================================================================
# Test Isolation Verification
# ============================================================================

# Verify that we are running in an isolated test environment
# Usage: assert_test_isolation (called automatically in setup, can be called manually)
assert_test_isolation() {
    # Verify we're not in the original working directory
    if [[ "$PWD" == "$ORIGINAL_PWD" ]] || [[ "$PWD" == "$PROJECT_ROOT" ]]; then
        echo "ERROR: Test is running in the original working directory!" >&2
        echo "  Current PWD: $PWD" >&2
        echo "  Original PWD: $ORIGINAL_PWD" >&2
        echo "  Tests must run in isolated temp directories." >&2
        return 1
    fi

    # Verify TEST_TEMP_DIR is set and we're inside it
    if [[ -z "$TEST_TEMP_DIR" ]] || [[ ! -d "$TEST_TEMP_DIR" ]]; then
        echo "ERROR: TEST_TEMP_DIR is not set or does not exist!" >&2
        return 1
    fi

    # Verify V0_TEST_MODE is enabled
    if [[ "$V0_TEST_MODE" != "1" ]]; then
        echo "ERROR: V0_TEST_MODE is not enabled!" >&2
        return 1
    fi

    return 0
}

# Assert that no files were created in the project root during tests
# Usage: assert_no_project_root_changes
assert_no_project_root_changes() {
    local new_files
    new_files=$(cd "$PROJECT_ROOT" && git status --porcelain 2>/dev/null | grep "^??" | wc -l)
    if [[ "$new_files" -gt 0 ]]; then
        echo "ERROR: New files were created in the project root during tests!" >&2
        (cd "$PROJECT_ROOT" && git status --porcelain | grep "^??") >&2
        return 1
    fi
    return 0
}

# Verify test environment variables are properly set
# Usage: assert_test_env
assert_test_env() {
    local errors=0

    if [[ "$V0_TEST_MODE" != "1" ]]; then
        echo "ERROR: V0_TEST_MODE should be 1, got: $V0_TEST_MODE" >&2
        errors=$((errors + 1))
    fi

    if [[ "$V0_NO_NOTIFICATIONS" != "1" ]]; then
        echo "ERROR: V0_NO_NOTIFICATIONS should be 1, got: $V0_NO_NOTIFICATIONS" >&2
        errors=$((errors + 1))
    fi

    if [[ -z "$TEST_TEMP_DIR" ]]; then
        echo "ERROR: TEST_TEMP_DIR is not set" >&2
        errors=$((errors + 1))
    fi

    return $errors
}
