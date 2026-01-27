#!/usr/bin/env bats
# Tests for config.sh - Configuration functions

load '../../test-support/helpers/test_helper'

# ============================================================================
# Setup/Teardown
# ============================================================================

setup() {
    _base_setup
    source_lib "grep.sh"
    source_lib "config.sh"
}

# ============================================================================
# v0_generate_user_branch() tests
# ============================================================================

@test "v0_generate_user_branch returns v0/agent/ prefix" {
    result=$(v0_generate_user_branch)
    [[ "$result" == v0/agent/* ]]
}

@test "v0_generate_user_branch includes username" {
    local username
    username=$(whoami | tr '[:upper:]' '[:lower:]')

    result=$(v0_generate_user_branch)
    [[ "$result" == v0/agent/${username}-* ]]
}

@test "v0_generate_user_branch includes 4-char hex id" {
    result=$(v0_generate_user_branch)

    # Extract the suffix after the last dash
    local suffix
    suffix="${result##*-}"

    # Should be 4 hex characters (2 bytes from xxd -p)
    [[ ${#suffix} -eq 4 ]]
    [[ "$suffix" =~ ^[0-9a-f]{4}$ ]]
}

@test "v0_generate_user_branch generates unique values" {
    local result1 result2
    result1=$(v0_generate_user_branch)
    result2=$(v0_generate_user_branch)

    # The two calls should generate different IDs
    [[ "$result1" != "$result2" ]]
}

# ============================================================================
# v0_worker_branch() tests
# ============================================================================

@test "v0_worker_branch returns bugs suffix for fix type" {
    V0_DEVELOP_BRANCH="v0/agent/alice-1234"
    result=$(v0_worker_branch "fix")
    [[ "$result" == "v0/agent/alice-1234-bugs" ]]
}

@test "v0_worker_branch returns chores suffix for chore type" {
    V0_DEVELOP_BRANCH="v0/agent/alice-1234"
    result=$(v0_worker_branch "chore")
    [[ "$result" == "v0/agent/alice-1234-chores" ]]
}

@test "v0_worker_branch works with v0/develop branch" {
    V0_DEVELOP_BRANCH="v0/develop"
    result=$(v0_worker_branch "fix")
    [[ "$result" == "v0/develop-bugs" ]]
}

@test "v0_worker_branch defaults to main when V0_DEVELOP_BRANCH unset" {
    unset V0_DEVELOP_BRANCH
    result=$(v0_worker_branch "fix")
    [[ "$result" == "main-bugs" ]]
}

@test "v0_worker_branch handles custom worker types" {
    V0_DEVELOP_BRANCH="v0/agent/bob-5678"
    result=$(v0_worker_branch "custom")
    [[ "$result" == "v0/agent/bob-5678-custom" ]]
}

# ============================================================================
# v0_infer_workspace_mode() tests
# ============================================================================

@test "v0_infer_workspace_mode returns clone for main" {
    result=$(v0_infer_workspace_mode "main")
    [[ "$result" == "clone" ]]
}

@test "v0_infer_workspace_mode returns clone for develop" {
    result=$(v0_infer_workspace_mode "develop")
    [[ "$result" == "clone" ]]
}

@test "v0_infer_workspace_mode returns clone for master" {
    result=$(v0_infer_workspace_mode "master")
    [[ "$result" == "clone" ]]
}

@test "v0_infer_workspace_mode returns worktree for v0/develop" {
    result=$(v0_infer_workspace_mode "v0/develop")
    [[ "$result" == "worktree" ]]
}

@test "v0_infer_workspace_mode returns worktree for v0/agent/*" {
    result=$(v0_infer_workspace_mode "v0/agent/alice-1234")
    [[ "$result" == "worktree" ]]
}

@test "v0_infer_workspace_mode returns worktree for feature branches" {
    result=$(v0_infer_workspace_mode "feature/my-feature")
    [[ "$result" == "worktree" ]]
}

# ============================================================================
# v0_init_agent_remote() tests
# ============================================================================

@test "v0_init_agent_remote creates bare repository" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    v0_init_agent_remote "${project_dir}" "${state_dir}"

    # Check that bare repo was created
    assert_dir_exists "${state_dir}/remotes/agent.git"

    # Verify it's a bare repository
    run git -C "${state_dir}/remotes/agent.git" rev-parse --is-bare-repository
    assert_success
    assert_output "true"
}

@test "v0_init_agent_remote adds agent remote to project" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    v0_init_agent_remote "${project_dir}" "${state_dir}"

    # Check that agent remote exists
    run git -C "${project_dir}" remote get-url agent
    assert_success
    assert_output "${state_dir}/remotes/agent.git"
}

@test "v0_init_agent_remote is idempotent" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    # Call twice
    v0_init_agent_remote "${project_dir}" "${state_dir}"
    v0_init_agent_remote "${project_dir}" "${state_dir}"

    # Should still work
    run git -C "${project_dir}" remote get-url agent
    assert_success
}

@test "v0_init_agent_remote skips if agent.git exists" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    mkdir -p "${project_dir}"
    mkdir -p "${state_dir}/remotes/agent.git"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    # Should return early without error
    run v0_init_agent_remote "${project_dir}" "${state_dir}"
    assert_success
}

# ============================================================================
# v0_ensure_develop_branch() tests
# ============================================================================

@test "v0_ensure_develop_branch creates v0/agent branch from HEAD" {
    local project_dir="${TEST_TEMP_DIR}/project"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    cd "${project_dir}" || return 1
    v0_ensure_develop_branch "v0/agent/test-1234" "origin"

    # Check branch was created
    run git -C "${project_dir}" branch --list "v0/agent/test-1234"
    assert_success
    [[ -n "$output" ]]
}

@test "v0_ensure_develop_branch skips remote check for v0/agent/* branches" {
    local project_dir="${TEST_TEMP_DIR}/project"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    # No remote configured - should still succeed for v0/agent/* branches
    cd "${project_dir}" || return 1
    run v0_ensure_develop_branch "v0/agent/alice-abcd" "origin"
    assert_success
}

@test "v0_ensure_develop_branch is idempotent" {
    local project_dir="${TEST_TEMP_DIR}/project"

    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    cd "${project_dir}" || return 1
    v0_ensure_develop_branch "v0/agent/test-5678" "origin"
    v0_ensure_develop_branch "v0/agent/test-5678" "origin"

    # Should still have one branch
    run git -C "${project_dir}" branch --list "v0/agent/test-5678"
    assert_success
    [[ $(echo "$output" | wc -l | tr -d ' ') -eq 1 ]]
}

# ============================================================================
# v0_load_config auto-create agent remote tests
# ============================================================================

@test "v0_load_config auto-creates agent remote when missing" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    # Create a git repo with .v0.rc configured for agent remote
    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    cat > "${project_dir}/.v0.rc" <<EOF
PROJECT="testproj"
ISSUE_PREFIX="test"
V0_GIT_REMOTE="agent"
EOF

    # Verify agent remote does NOT exist yet
    run git -C "${project_dir}" remote get-url agent
    assert_failure

    # Set up environment for v0_load_config
    cd "${project_dir}" || return 1
    export XDG_STATE_HOME="${state_dir}"

    # Source config.sh which defines v0_load_config
    source "${PROJECT_ROOT}/packages/core/lib/grep.sh"
    source "${PROJECT_ROOT}/packages/core/lib/config.sh"

    # Call v0_load_config - this should auto-create the agent remote
    v0_load_config

    # Verify agent remote now exists
    run git -C "${project_dir}" remote get-url agent
    assert_success
    assert_output --partial "remotes/agent.git"
}

@test "v0_load_config skips agent remote creation when remote already exists" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"
    local agent_dir="${state_dir}/v0/testproj/remotes/agent.git"

    # Create a git repo
    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    cat > "${project_dir}/.v0.rc" <<EOF
PROJECT="testproj"
ISSUE_PREFIX="test"
V0_GIT_REMOTE="agent"
EOF

    # Pre-create the agent remote
    mkdir -p "${agent_dir}"
    git -C "${project_dir}" clone --bare "${project_dir}" "${agent_dir}" 2>/dev/null
    git -C "${project_dir}" remote add agent "${agent_dir}"

    # Set up environment
    cd "${project_dir}" || return 1
    export XDG_STATE_HOME="${state_dir}"

    # Source and call v0_load_config
    source "${PROJECT_ROOT}/packages/core/lib/grep.sh"
    source "${PROJECT_ROOT}/packages/core/lib/config.sh"

    # Should succeed without error (idempotent)
    run v0_load_config
    assert_success

    # Verify remote still exists and points to same place
    run git -C "${project_dir}" remote get-url agent
    assert_success
    assert_output "${agent_dir}"
}

@test "v0_load_config skips agent remote creation when V0_GIT_REMOTE is not agent" {
    local project_dir="${TEST_TEMP_DIR}/project"
    local state_dir="${TEST_TEMP_DIR}/state"

    # Create a git repo configured for origin remote
    mkdir -p "${project_dir}"
    git -C "${project_dir}" init --initial-branch=main
    git -C "${project_dir}" commit --allow-empty -m "Initial commit"

    cat > "${project_dir}/.v0.rc" <<EOF
PROJECT="testproj"
ISSUE_PREFIX="test"
V0_GIT_REMOTE="origin"
EOF

    # Set up environment
    cd "${project_dir}" || return 1
    export XDG_STATE_HOME="${state_dir}"

    # Source and call v0_load_config
    source "${PROJECT_ROOT}/packages/core/lib/grep.sh"
    source "${PROJECT_ROOT}/packages/core/lib/config.sh"

    v0_load_config

    # Verify agent remote was NOT created (V0_GIT_REMOTE is "origin", not "agent")
    run git -C "${project_dir}" remote get-url agent
    assert_failure
}
