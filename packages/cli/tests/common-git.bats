#!/usr/bin/env bats
# Tests for git-related utility functions

load '../../test-support/helpers/test_helper'
load 'helpers'

# ============================================================================
# v0_git_worktree_clean() tests
# ============================================================================

@test "v0_git_worktree_clean returns 0 for clean repo" {
    setup_git_repo
    run v0_git_worktree_clean .
    assert_success
}

@test "v0_git_worktree_clean returns 1 for repo with staged changes" {
    setup_git_repo
    echo "new content" > newfile.txt
    git add newfile.txt
    run v0_git_worktree_clean .
    assert_failure
}

@test "v0_git_worktree_clean returns 1 for repo with unstaged changes" {
    setup_git_repo
    echo "modified" >> README.md
    run v0_git_worktree_clean .
    assert_failure
}

@test "v0_git_worktree_clean accepts directory argument" {
    init_mock_git_repo "${TEST_TEMP_DIR}/project"
    source_lib "v0-common.sh"
    run v0_git_worktree_clean "${TEST_TEMP_DIR}/project"
    assert_success
}

@test "v0_git_worktree_clean returns 1 for non-git directory" {
    source_lib "v0-common.sh"
    mkdir -p "${TEST_TEMP_DIR}/not-a-repo"

    # Should return 1 (dirty/cannot verify) for non-git directories
    run v0_git_worktree_clean "${TEST_TEMP_DIR}/not-a-repo"
    assert_failure
}

# ============================================================================
# v0_verify_push() tests
# ============================================================================

@test "v0_verify_push returns 0 for commit on main" {
    setup_git_repo
    run v0_verify_push "$(git rev-parse HEAD)"
    assert_success
}

@test "v0_verify_push returns 1 for commit not on main" {
    setup_git_repo
    git checkout -b feature
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "Feature commit"
    local feature_commit
    feature_commit=$(git rev-parse HEAD)
    git checkout main
    run v0_verify_push "${feature_commit}"
    assert_failure
    assert_output --partial "is not on main branch"
}

@test "v0_verify_push returns 1 for nonexistent commit" {
    setup_git_repo
    run v0_verify_push "1234567890abcdef1234567890abcdef12345678"
    assert_failure
    assert_output --partial "does not exist locally"
}

@test "v0_verify_push respects V0_DEVELOP_BRANCH" {
    setup_git_repo
    git checkout -b develop
    echo "develop" > develop.txt
    git add develop.txt
    git commit -m "Develop commit"
    local develop_commit
    develop_commit=$(git rev-parse HEAD)
    export V0_DEVELOP_BRANCH="develop"
    run v0_verify_push "${develop_commit}"
    assert_success
    git checkout main
    export V0_DEVELOP_BRANCH="main"
    run v0_verify_push "${develop_commit}"
    assert_failure
    assert_output --partial "is not on main branch"
}

# ============================================================================
# v0_diagnose_push_verification() tests
# ============================================================================

@test "v0_diagnose_push_verification outputs diagnostic info and shows commit existence" {
    source_lib "v0-common.sh"
    init_git_repo_with_remote
    local branch commit
    branch=$(git rev-parse --abbrev-ref HEAD)
    commit=$(git rev-parse HEAD)

    run v0_diagnose_push_verification "${commit}" "origin/${branch}"

    # Check diagnostic sections are present
    assert_output --partial "Push Verification Diagnostic"
    assert_output --partial "Commit to verify:"
    assert_output --partial "Local refs:"
    assert_output --partial "Remote state"
    assert_output --partial "Ancestry check:"
    assert_output --partial "exists locally"
}

@test "v0_diagnose_push_verification handles missing commit" {
    source_lib "v0-common.sh"
    init_git_repo_with_remote
    local branch fake_commit
    branch=$(git rev-parse --abbrev-ref HEAD)
    fake_commit="1234567890abcdef1234567890abcdef12345678"

    run v0_diagnose_push_verification "${fake_commit}" "origin/${branch}"
    assert_output --partial "NOT FOUND locally"
}
