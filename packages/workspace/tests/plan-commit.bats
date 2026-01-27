#!/usr/bin/env bats
# plan-commit.bats - Tests for plan commit functions

load '../../test-support/helpers/test_helper'

setup() {
    _base_setup
    setup_v0_env

    # Set up workspace-specific variables
    export V0_WORKSPACE_MODE="clone"
    export V0_WORKSPACE_DIR="$V0_STATE_DIR/workspace/testrepo"
    export REPO_NAME="testrepo"
    export V0_GIT_REMOTE="origin"
    export V0_DEVELOP_BRANCH="main"
    export V0_PLANS_DIR="plans"

    # Initialize a real git repo with a remote
    cd "$TEST_TEMP_DIR/project"
    git init --quiet -b main
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit --quiet -m "Initial commit"

    # Create a bare remote for push/pull testing
    REMOTE_DIR="$TEST_TEMP_DIR/remote.git"
    git clone --bare "$TEST_TEMP_DIR/project" "$REMOTE_DIR" 2>/dev/null
    git -C "$TEST_TEMP_DIR/project" remote add origin "$REMOTE_DIR"

    # Source workspace library
    source "$PROJECT_ROOT/packages/workspace/lib/workspace.sh"
}

# ============================================================================
# ws_commit_plan_to_develop Tests
# ============================================================================

@test "ws_commit_plan_to_develop requires name argument" {
    run ws_commit_plan_to_develop "" "/tmp/test.md"
    assert_failure
    assert_output --partial "requires <name> <source_file>"
}

@test "ws_commit_plan_to_develop requires source_file argument" {
    run ws_commit_plan_to_develop "test-plan" ""
    assert_failure
    assert_output --partial "requires <name> <source_file>"
}

@test "ws_commit_plan_to_develop fails if source file missing" {
    run ws_commit_plan_to_develop "test-plan" "/nonexistent/file.md"
    assert_failure
    assert_output --partial "Source file does not exist"
}

@test "ws_commit_plan_to_develop commits plan to workspace" {
    # Create a plan file
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan" > "$plan_file"

    run ws_commit_plan_to_develop "test-plan" "$plan_file"
    assert_success

    # Verify plan exists in workspace
    assert_file_exists "$V0_WORKSPACE_DIR/plans/test-plan.md"

    # Verify plan was committed
    local commit_msg
    commit_msg=$(git -C "$V0_WORKSPACE_DIR" log -1 --pretty=%s)
    assert_equal "$commit_msg" "Add plan: test-plan"
}

@test "ws_commit_plan_to_develop is idempotent for unchanged plan" {
    # Create a plan file
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan" > "$plan_file"

    # First commit
    ws_commit_plan_to_develop "test-plan" "$plan_file"

    # Second commit with same content should succeed
    run ws_commit_plan_to_develop "test-plan" "$plan_file"
    assert_success
}

@test "ws_commit_plan_to_develop updates existing plan" {
    # Create and commit initial plan
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan v1" > "$plan_file"
    ws_commit_plan_to_develop "test-plan" "$plan_file"

    # Update plan
    echo "# Test Plan v2" > "$plan_file"
    run ws_commit_plan_to_develop "test-plan" "$plan_file"
    assert_success

    # Verify updated content
    local content
    content=$(cat "$V0_WORKSPACE_DIR/plans/test-plan.md")
    assert_equal "$content" "# Test Plan v2"
}

@test "ws_commit_plan_to_develop pushes to remote" {
    # Create a plan file
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan" > "$plan_file"

    ws_commit_plan_to_develop "test-plan" "$plan_file"

    # Verify plan exists on remote
    run git -C "$REMOTE_DIR" show main:plans/test-plan.md
    assert_success
    assert_output "# Test Plan"
}

# ============================================================================
# ws_get_plan_from_develop Tests
# ============================================================================

@test "ws_get_plan_from_develop requires name argument" {
    run ws_get_plan_from_develop "" "/tmp/dest.md"
    assert_failure
    assert_output --partial "requires <name> <dest_file>"
}

@test "ws_get_plan_from_develop requires dest_file argument" {
    run ws_get_plan_from_develop "test-plan" ""
    assert_failure
    assert_output --partial "requires <name> <dest_file>"
}

@test "ws_get_plan_from_develop fails if plan not found" {
    # Ensure workspace exists
    ws_ensure_workspace

    run ws_get_plan_from_develop "nonexistent-plan" "$TEST_TEMP_DIR/dest.md"
    assert_failure
}

@test "ws_get_plan_from_develop retrieves plan from workspace" {
    # First commit a plan
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan Content" > "$plan_file"
    ws_commit_plan_to_develop "test-plan" "$plan_file"

    # Retrieve it
    local dest_file="$TEST_TEMP_DIR/retrieved.md"
    run ws_get_plan_from_develop "test-plan" "$dest_file"
    assert_success

    # Verify content
    local content
    content=$(cat "$dest_file")
    assert_equal "$content" "# Test Plan Content"
}

@test "ws_get_plan_from_develop creates destination directory" {
    # First commit a plan
    local plan_file="$TEST_TEMP_DIR/test-plan.md"
    echo "# Test Plan" > "$plan_file"
    ws_commit_plan_to_develop "test-plan" "$plan_file"

    # Retrieve to nested path
    local dest_file="$TEST_TEMP_DIR/nested/dir/retrieved.md"
    run ws_get_plan_from_develop "test-plan" "$dest_file"
    assert_success
    assert_file_exists "$dest_file"
}

# ============================================================================
# Concurrent Push Retry Tests
# ============================================================================

@test "ws_commit_plan_to_develop handles concurrent push via retry" {
    # Create first plan
    local plan1="$TEST_TEMP_DIR/plan1.md"
    echo "# Plan 1" > "$plan1"
    ws_commit_plan_to_develop "plan1" "$plan1"

    # Simulate another commit pushed to remote by cloning and pushing directly
    local other_clone="$TEST_TEMP_DIR/other-clone"
    git clone "$REMOTE_DIR" "$other_clone" 2>/dev/null
    git -C "$other_clone" config user.email "other@example.com"
    git -C "$other_clone" config user.name "Other User"
    mkdir -p "$other_clone/plans"
    echo "# Other Plan" > "$other_clone/plans/other-plan.md"
    git -C "$other_clone" add plans/other-plan.md
    git -C "$other_clone" commit -m "Add other plan" --quiet
    git -C "$other_clone" push origin main --quiet

    # Now our workspace is behind - next commit should retry
    local plan2="$TEST_TEMP_DIR/plan2.md"
    echo "# Plan 2" > "$plan2"
    run ws_commit_plan_to_develop "plan2" "$plan2"
    assert_success

    # Verify both plans exist on remote
    run git -C "$REMOTE_DIR" show main:plans/plan2.md
    assert_success
}
