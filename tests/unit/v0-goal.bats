#!/usr/bin/env bats
# v0-goal.bats - Tests for v0-goal command

load '../helpers/test_helper'

# Path to the script under test
V0_GOAL="${PROJECT_ROOT}/bin/v0-goal"

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    mkdir -p "${TEST_TEMP_DIR}/project/.v0/build/goals" "${TEST_TEMP_DIR}/state"

    export REAL_HOME="${HOME}"
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "${HOME}/.local/state/v0"

    export V0_TEST_MODE=1
    export V0_NO_NOTIFICATIONS=1

    # Clear inherited v0 state variables
    unset V0_ROOT
    unset PROJECT
    unset ISSUE_PREFIX
    unset BUILD_DIR
    unset PLANS_DIR
    unset V0_STATE_DIR

    # Create minimal .v0.rc
    cat > "${TEST_TEMP_DIR}/project/.v0.rc" <<EOF
PROJECT="testproject"
ISSUE_PREFIX="test"
REPO_NAME="testrepo"
V0_ROOT="${TEST_TEMP_DIR}/project"
V0_STATE_DIR="${TEST_TEMP_DIR}/state/testproject"
EOF
    mkdir -p "${TEST_TEMP_DIR}/state/testproject"

    cd "${TEST_TEMP_DIR}/project" || exit 1
    export ORIGINAL_PATH="${PATH}"

    # Initialize git repo
    git init --quiet -b main
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"

    # Track mock calls
    export MOCK_CALLS_DIR="${TEST_TEMP_DIR}/mock-calls"
    mkdir -p "${MOCK_CALLS_DIR}"

    # Create mock tmux that reports no sessions
    mkdir -p "${TEST_TEMP_DIR}/mock-v0-bin"
    cat > "${TEST_TEMP_DIR}/mock-v0-bin/tmux" <<'EOF'
#!/bin/bash
echo "tmux $*" >> "$MOCK_CALLS_DIR/tmux.calls" 2>/dev/null || true
if [[ "$1" == "has-session" ]]; then
    exit 1  # No session exists
fi
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/mock-v0-bin/tmux"

    # Create mock claude
    cat > "${TEST_TEMP_DIR}/mock-v0-bin/claude" <<'EOF'
#!/bin/bash
echo "claude $*" >> "$MOCK_CALLS_DIR/claude.calls" 2>/dev/null || true
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/mock-v0-bin/claude"

    # Create mock wk that returns a fake idea ID
    cat > "${TEST_TEMP_DIR}/mock-v0-bin/wk" <<'EOF'
#!/bin/bash
echo "wk $*" >> "$MOCK_CALLS_DIR/wk.calls" 2>/dev/null || true
if [[ "$1" == "new" ]] && [[ "$2" == "idea" ]]; then
    echo "Created test-abc123"
fi
if [[ "$1" == "list" ]]; then
    echo ""
fi
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/mock-v0-bin/wk"

    # Create mock m4
    cat > "${TEST_TEMP_DIR}/mock-v0-bin/m4" <<'EOF'
#!/bin/bash
echo "m4 $*" >> "$MOCK_CALLS_DIR/m4.calls" 2>/dev/null || true
# Output a minimal CLAUDE.md
echo "## Your Mission"
echo "Test goal"
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/mock-v0-bin/m4"

    # Create mock jq (use real jq if available, otherwise simple mock)
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "${TEST_TEMP_DIR}/mock-v0-bin/jq"
    fi

    export PATH="${TEST_TEMP_DIR}/mock-v0-bin:${PATH}"
}

teardown() {
    export HOME="${REAL_HOME}"
    export PATH="${ORIGINAL_PATH}"
    if [[ -n "${TEST_TEMP_DIR}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# ============================================================================
# Help and Usage Tests
# ============================================================================

@test "v0-goal: --help shows usage" {
    run "${V0_GOAL}" --help 2>&1 || true
    assert_output --partial "Usage: v0 goal"
}

@test "v0-goal: no arguments shows usage error" {
    run "${V0_GOAL}" 2>&1 || true
    assert_failure
    assert_output --partial "Usage: v0 goal"
}

@test "v0-goal: --status with no goals shows empty" {
    run "${V0_GOAL}" --status
    assert_success
    # Output shows "Goals:" header and "(none)" when empty
    assert_output --partial "(none)"
}

# ============================================================================
# Name Validation Tests
# ============================================================================

@test "v0-goal: rejects invalid name with spaces" {
    run "${V0_GOAL}" "invalid name" "Description" 2>&1
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "v0-goal: rejects name starting with number" {
    run "${V0_GOAL}" "123goal" "Description" 2>&1
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "v0-goal: rejects name starting with underscore" {
    run "${V0_GOAL}" "_goal" "Description" 2>&1
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "v0-goal: accepts valid name with letters and hyphens" {
    run "${V0_GOAL}" "my-goal" "Test description" --dry-run
    assert_success
}

@test "v0-goal: accepts valid name with letters and numbers" {
    run "${V0_GOAL}" "goal123" "Test description" --dry-run
    assert_success
}

# ============================================================================
# Dry Run Tests
# ============================================================================

@test "v0-goal: --dry-run creates state directory" {
    run "${V0_GOAL}" test-goal "Test goal description" --dry-run
    assert_success
    assert_output --partial "Creating goal"
    assert [ -d "${TEST_TEMP_DIR}/project/.v0/build/goals/test-goal" ]
}

@test "v0-goal: --dry-run creates state.json" {
    run "${V0_GOAL}" test-goal "Test goal description" --dry-run
    assert_success
    assert [ -f "${TEST_TEMP_DIR}/project/.v0/build/goals/test-goal/state.json" ]
}

@test "v0-goal: --dry-run state contains goal_description" {
    run "${V0_GOAL}" test-goal "My amazing goal" --dry-run
    assert_success
    run jq -r '.goal_description' "${TEST_TEMP_DIR}/project/.v0/build/goals/test-goal/state.json"
    assert_output "My amazing goal"
}

@test "v0-goal: --dry-run state contains correct name" {
    run "${V0_GOAL}" mygoal "Some description" --dry-run
    assert_success
    run jq -r '.name' "${TEST_TEMP_DIR}/project/.v0/build/goals/mygoal/state.json"
    assert_output "mygoal"
}

@test "v0-goal: --dry-run state has init phase" {
    run "${V0_GOAL}" test-goal "Test" --dry-run
    assert_success
    run jq -r '.phase' "${TEST_TEMP_DIR}/project/.v0/build/goals/test-goal/state.json"
    assert_output "init"
}

@test "v0-goal: --dry-run does not launch worker" {
    run "${V0_GOAL}" test-goal "Test goal" --dry-run
    assert_success
    assert_output --partial "Dry run complete"
    # No tmux calls should be made
    assert [ ! -f "${MOCK_CALLS_DIR}/tmux.calls" ] || ! grep -q "new-session" "${MOCK_CALLS_DIR}/tmux.calls"
}

# ============================================================================
# Duplicate Goal Tests
# ============================================================================

@test "v0-goal: rejects duplicate goal name" {
    # Create first goal
    run "${V0_GOAL}" mygoal "First goal" --dry-run
    assert_success

    # Try to create second goal with same name
    run "${V0_GOAL}" mygoal "Second goal" --dry-run 2>&1
    assert_failure
    assert_output --partial "already exists"
}

# ============================================================================
# Resume Tests
# ============================================================================

@test "v0-goal: --resume fails for non-existent goal" {
    run "${V0_GOAL}" nonexistent --resume 2>&1
    assert_failure
    assert_output --partial "No goal found"
}

@test "v0-goal: --resume works for existing goal" {
    # Create goal first
    run "${V0_GOAL}" mygoal "Test" --dry-run
    assert_success

    # Now resume should work (in dry-run context we just check it finds the goal)
    run "${V0_GOAL}" mygoal --resume 2>&1
    # It should find the goal and try to resume
    assert_output --partial "Resuming goal"
}

# ============================================================================
# Status Display Tests
# ============================================================================

@test "v0-goal: --status shows existing goals" {
    # Create a goal
    run "${V0_GOAL}" mygoal "Test description" --dry-run
    assert_success

    # Status should show it
    run "${V0_GOAL}" --status
    assert_success
    assert_output --partial "mygoal"
}

@test "v0-goal: --status shows goal phase" {
    # Create a goal
    run "${V0_GOAL}" mygoal "Test description" --dry-run
    assert_success

    # Status should show the phase
    run "${V0_GOAL}" --status
    assert_success
    assert_output --partial "init"
}

# ============================================================================
# wk Idea Integration Tests
# ============================================================================

@test "v0-goal: creates wk idea issue" {
    run "${V0_GOAL}" mygoal "Test goal" --dry-run
    assert_success

    # Check that wk new idea was called
    assert [ -f "${MOCK_CALLS_DIR}/wk.calls" ]
    run grep "new idea" "${MOCK_CALLS_DIR}/wk.calls"
    assert_success
}

@test "v0-goal: idea label includes goal name" {
    run "${V0_GOAL}" mygoal "Test goal" --dry-run
    assert_success

    # Check that the goal label was included
    run grep "goal:mygoal" "${MOCK_CALLS_DIR}/wk.calls"
    assert_success
}
