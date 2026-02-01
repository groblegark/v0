#!/usr/bin/env bats
# Tests for project discovery functions

load '../../test-support/helpers/test_helper'
load 'helpers'

# ============================================================================
# v0_find_project_root() tests
# ============================================================================

@test "v0_find_project_root finds .v0.rc in current directory" {
    touch "${TEST_TEMP_DIR}/project/.v0.rc"
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    run v0_find_project_root
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}

@test "v0_find_project_root finds .v0.rc in parent directory" {
    touch "${TEST_TEMP_DIR}/project/.v0.rc"
    mkdir -p "${TEST_TEMP_DIR}/project/src/deep/nested"
    cd "${TEST_TEMP_DIR}/project/src/deep/nested" || return 1
    source_lib "v0-common.sh"

    run v0_find_project_root
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}

@test "v0_find_project_root finds .v0.rc from arbitrary nested path" {
    touch "${TEST_TEMP_DIR}/project/.v0.rc"
    mkdir -p "${TEST_TEMP_DIR}/project/a/b/c/d/e"
    cd "${TEST_TEMP_DIR}/project/a/b/c/d/e" || return 1
    source_lib "v0-common.sh"

    run v0_find_project_root
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}

@test "v0_find_project_root fails without .v0.rc" {
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    run v0_find_project_root
    assert_failure
}

@test "v0_find_project_root accepts start directory argument" {
    touch "${TEST_TEMP_DIR}/project/.v0.rc"
    mkdir -p "${TEST_TEMP_DIR}/project/subdir"
    source_lib "v0-common.sh"

    run v0_find_project_root "${TEST_TEMP_DIR}/project/subdir"
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}

# ============================================================================
# v0_find_main_repo() tests
# ============================================================================

@test "v0_find_main_repo returns same directory for main repo" {
    setup_git_repo
    run v0_find_main_repo "${TEST_TEMP_DIR}/project"
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}

@test "v0_find_main_repo returns main repo from worktree" {
    init_mock_git_repo "${TEST_TEMP_DIR}/project"
    cd "${TEST_TEMP_DIR}/project" || return 1

    # Get the default branch name (main or master depending on git version)
    local default_branch
    default_branch=$(git rev-parse --abbrev-ref HEAD)

    # Create a worktree on a new branch
    mkdir -p "${TEST_TEMP_DIR}/worktrees"
    git worktree add -b feature-branch "${TEST_TEMP_DIR}/worktrees/feature"

    source_lib "v0-common.sh"

    # From worktree, should return main repo
    # Note: resolve symlinks in expected path (macOS /var -> /private/var)
    local expected_path
    expected_path=$(cd "${TEST_TEMP_DIR}/project" && pwd -P)

    run v0_find_main_repo "${TEST_TEMP_DIR}/worktrees/feature"
    assert_success
    assert_output "${expected_path}"
}

@test "v0_find_main_repo returns input directory for non-git directory" {
    mkdir -p "${TEST_TEMP_DIR}/not-a-repo"
    source_lib "v0-common.sh"

    run v0_find_main_repo "${TEST_TEMP_DIR}/not-a-repo"
    assert_success
    assert_output "${TEST_TEMP_DIR}/not-a-repo"
}

@test "v0_find_main_repo uses V0_ROOT when no argument given" {
    setup_git_repo
    export V0_ROOT="${TEST_TEMP_DIR}/project"
    run v0_find_main_repo
    assert_success
    assert_output "${TEST_TEMP_DIR}/project"
}
