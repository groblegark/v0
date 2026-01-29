#!/usr/bin/env bats
# Tests for v0 configuration loading and initialization

load '../../test-support/helpers/test_helper'
load 'helpers'

# ============================================================================
# v0_load_config() tests
# ============================================================================

@test "v0_load_config loads valid configuration" {
    create_v0rc "testproject" "testp"
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${PROJECT}" "testproject"
    assert_equal "${ISSUE_PREFIX}" "testp"
}

@test "v0_load_config sets V0_ROOT correctly" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${V0_ROOT}" "${TEST_TEMP_DIR}/project"
}

@test "v0_load_config ignores inherited V0_ROOT from environment" {
    # Create two separate projects
    mkdir -p "${TEST_TEMP_DIR}/project-a"
    mkdir -p "${TEST_TEMP_DIR}/project-b"

    # Set up project-a with its own .v0.rc
    cat > "${TEST_TEMP_DIR}/project-a/.v0.rc" <<'EOF'
PROJECT="project-a"
ISSUE_PREFIX="pa"
EOF

    # Set up project-b with its own .v0.rc
    cat > "${TEST_TEMP_DIR}/project-b/.v0.rc" <<'EOF'
PROJECT="project-b"
ISSUE_PREFIX="pb"
EOF

    # Set V0_ROOT to point to project-b (simulating inherited environment)
    export V0_ROOT="${TEST_TEMP_DIR}/project-b"
    export BUILD_DIR="${TEST_TEMP_DIR}/project-b/.v0/build"
    export PROJECT="project-b"

    # cd to project-a and load config
    cd "${TEST_TEMP_DIR}/project-a" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    # Verify that we're using project-a, NOT the inherited project-b values
    assert_equal "${V0_ROOT}" "${TEST_TEMP_DIR}/project-a"
    assert_equal "${PROJECT}" "project-a"
    assert_equal "${ISSUE_PREFIX}" "pa"
    assert_equal "${BUILD_DIR}" "${TEST_TEMP_DIR}/project-a/.v0/build"
}

@test "v0_load_config sets derived values" {
    create_v0rc "myproj" "mp"
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${REPO_NAME}" "project"
    assert_equal "${BUILD_DIR}" "${TEST_TEMP_DIR}/project/.v0/build"
    assert_equal "${PLANS_DIR}" "${TEST_TEMP_DIR}/project/plans"
}

@test "v0_load_config fails without PROJECT" {
    # Create isolated temp directory structure that doesn't traverse to real .v0.rc
    local isolated_dir="${TEST_TEMP_DIR}/isolated"
    mkdir -p "${isolated_dir}/project"
    echo 'ISSUE_PREFIX="test"' > "${isolated_dir}/project/.v0.rc"

    # v0_load_config calls exit 1 on error, so we need to run it in a subshell
    # Unset PROJECT and ISSUE_PREFIX to test validation (they may be inherited from parent env)
    run env -u PROJECT -u ISSUE_PREFIX bash -c 'cd "'"${isolated_dir}/project"'" && source "'"${PROJECT_ROOT}"'/packages/cli/lib/v0-common.sh" && v0_load_config'
    assert_failure
    assert_output --partial "PROJECT"
}

@test "v0_load_config fails without ISSUE_PREFIX" {
    # Create isolated temp directory structure that doesn't traverse to real .v0.rc
    local isolated_dir="${TEST_TEMP_DIR}/isolated"
    mkdir -p "${isolated_dir}/project"
    echo 'PROJECT="testproject"' > "${isolated_dir}/project/.v0.rc"

    # v0_load_config calls exit 1 on error, so we need to run it in a subshell
    # Unset PROJECT and ISSUE_PREFIX to test validation (they may be inherited from parent env)
    run env -u PROJECT -u ISSUE_PREFIX bash -c 'cd "'"${isolated_dir}/project"'" && source "'"${PROJECT_ROOT}"'/packages/cli/lib/v0-common.sh" && v0_load_config'
    assert_failure
    assert_output --partial "ISSUE_PREFIX"
}

@test "v0_load_config sets default values" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${V0_BUILD_DIR}" ".v0/build"
    assert_equal "${V0_PLANS_DIR}" "plans"
    assert_equal "${V0_FEATURE_BRANCH}" "feature/{name}"
}

@test "v0_load_config allows custom overrides" {
    cat > "${TEST_TEMP_DIR}/project/.v0.rc" <<'EOF'
PROJECT="customproj"
ISSUE_PREFIX="cust"
V0_BUILD_DIR=".build"
V0_PLANS_DIR="docs/plans"
EOF
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${V0_BUILD_DIR}" ".build"
    assert_equal "${V0_PLANS_DIR}" "docs/plans"
    assert_equal "${BUILD_DIR}" "${TEST_TEMP_DIR}/project/.build"
    assert_equal "${PLANS_DIR}" "${TEST_TEMP_DIR}/project/docs/plans"
}

@test "v0_load_config with require_config=false returns 1 without .v0.rc" {
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    run v0_load_config false
    assert_failure
    # Should not output error message when require_config is false
    refute_output --partial "Error"
}

@test "v0_load_config sets V0_DEVELOP_BRANCH default to main" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${V0_DEVELOP_BRANCH}" "main"
}

@test "v0_load_config allows V0_DEVELOP_BRANCH override" {
    create_v0rc
    echo 'V0_DEVELOP_BRANCH="develop"' >> "${TEST_TEMP_DIR}/project/.v0.rc"
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    assert_equal "${V0_DEVELOP_BRANCH}" "develop"
}

@test "v0_load_config exports V0_DEVELOP_BRANCH" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    # Verify it's exported by checking in subshell
    run bash -c 'echo "${V0_DEVELOP_BRANCH}"'
    assert_output "main"
}

@test "v0_load_config finds .v0.profile.rc in main repo when running from worktree" {
    # Create main repo with .v0.rc and .v0.profile.rc
    init_mock_git_repo "${TEST_TEMP_DIR}/project"
    cd "${TEST_TEMP_DIR}/project" || return 1
    create_v0rc "testproject" "testp"

    # Commit .v0.rc so it appears in worktrees
    git add .v0.rc
    git commit -m "Add .v0.rc"

    # Create .v0.profile.rc with custom develop branch (gitignored file, not committed)
    cat > "${TEST_TEMP_DIR}/project/.v0.profile.rc" <<'EOF'
export V0_DEVELOP_BRANCH="v0/agent/test-user-1234"
EOF

    # Create a worktree (simulating agent workspace)
    mkdir -p "${TEST_TEMP_DIR}/worktrees"
    git worktree add -b feature-branch "${TEST_TEMP_DIR}/worktrees/feature"

    # Verify .v0.profile.rc does NOT exist in worktree (it's gitignored)
    [[ ! -f "${TEST_TEMP_DIR}/worktrees/feature/.v0.profile.rc" ]]

    # Verify .v0.rc DOES exist in worktree (it's committed)
    [[ -f "${TEST_TEMP_DIR}/worktrees/feature/.v0.rc" ]]

    # Load config from worktree
    cd "${TEST_TEMP_DIR}/worktrees/feature" || return 1
    source_lib "v0-common.sh"

    v0_load_config

    # Should have loaded V0_DEVELOP_BRANCH from main repo's .v0.profile.rc
    assert_equal "${V0_DEVELOP_BRANCH}" "v0/agent/test-user-1234"
}

# ============================================================================
# v0_init_config() tests
# ============================================================================

@test "v0_init_config creates .v0.rc file" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    source_lib_with_mocks "v0-common.sh"

    run v0_init_config "${test_dir}"
    assert_success
    assert_file_exists "${test_dir}/.v0.rc"
}

@test "v0_init_config adds .v0/ to gitignore" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}"

    assert_file_exists "${test_dir}/.gitignore"
    run grep "^\.v0/" "${test_dir}/.gitignore"
    assert_success
}

@test "v0_init_config adds .v0/ to existing gitignore" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    echo "node_modules/" > "${test_dir}/.gitignore"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}"

    run grep "node_modules/" "${test_dir}/.gitignore"
    assert_success
    run grep "^\.v0/" "${test_dir}/.gitignore"
    assert_success
}

@test "v0_init_config does not duplicate .v0/ in gitignore" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    echo ".v0/" > "${test_dir}/.gitignore"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}"

    # Count occurrences of .v0/ - should be exactly 1
    local count
    count=$(grep -c "^\.v0/" "${test_dir}/.gitignore")
    assert_equal "${count}" "1"
}

# ============================================================================
# v0_detect_develop_branch() tests
# ============================================================================

@test "v0_detect_develop_branch returns develop when it exists locally" {
    setup_git_repo
    git branch develop
    run v0_detect_develop_branch
    assert_success
    assert_output "develop"
}

@test "v0_detect_develop_branch returns v0/develop when develop does not exist" {
    setup_git_repo
    run v0_detect_develop_branch
    assert_success
    assert_output "v0/develop"
}

@test "v0_detect_develop_branch checks remote when local branch not found" {
    init_mock_git_repo "${TEST_TEMP_DIR}/project"
    cd "${TEST_TEMP_DIR}/project" || return 1

    # Create a bare remote with develop branch
    git clone --bare . "${TEST_TEMP_DIR}/upstream.git"
    cd "${TEST_TEMP_DIR}/upstream.git" || return 1
    git branch develop

    cd "${TEST_TEMP_DIR}/project" || return 1
    git remote add upstream "${TEST_TEMP_DIR}/upstream.git"

    source_lib "v0-common.sh"

    run v0_detect_develop_branch upstream
    assert_success
    assert_output "develop"
}

# ============================================================================
# v0_init_config() with branch/remote parameters
# ============================================================================

@test "v0_init_config accepts develop branch parameter" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}" "staging"

    assert_file_exists "${test_dir}/.v0.rc"
    run grep 'V0_DEVELOP_BRANCH="staging"' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config accepts remote parameter" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}" "" "upstream"

    assert_file_exists "${test_dir}/.v0.rc"
    run grep 'V0_GIT_REMOTE="upstream"' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config generates unique user branch by default" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    init_mock_git_repo "${test_dir}"
    cd "${test_dir}" || return 1
    # Even if 'develop' branch exists, init should use v0/agent/*
    git branch develop

    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}"

    # Should use v0/agent/{username}-{id} pattern in .v0.profile.rc (auto-generated)
    run grep 'V0_DEVELOP_BRANCH="v0/agent/' "${test_dir}/.v0.profile.rc"
    assert_success
    # .v0.rc should source the profile instead
    run grep 'source.*\.v0\.profile\.rc' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config always writes V0_DEVELOP_BRANCH explicitly" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"

    source_lib_with_mocks "v0-common.sh"

    # Even with main specified, branch should be written explicitly
    v0_init_config "${test_dir}" "main" "origin"

    # Branch should always be explicit (not commented)
    run grep '^V0_DEVELOP_BRANCH="main"' "${test_dir}/.v0.rc"
    assert_success
    # Remote is always written explicitly now
    run grep '^V0_GIT_REMOTE="origin"' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config uses uncommented values for non-defaults" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    mkdir -p "${test_dir}"
    source_lib_with_mocks "v0-common.sh"

    v0_init_config "${test_dir}" "staging" "upstream"

    # Should be uncommented when using non-defaults
    run grep '^V0_DEVELOP_BRANCH="staging"' "${test_dir}/.v0.rc"
    assert_success
    run grep '^V0_GIT_REMOTE="upstream"' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config generates user-specific branch when develop does not exist" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    init_mock_git_repo "${test_dir}"
    cd "${test_dir}" || return 1

    # Mock wk to avoid actual wk initialization
    wk() { echo "mock wk $*"; return 0; }
    export -f wk

    source_lib "v0-common.sh"

    # Run init (should generate v0/agent/{username}-{id})
    v0_init_config "${test_dir}"

    # Verify .v0.profile.rc contains v0/agent/* pattern (auto-generated branch)
    run grep 'V0_DEVELOP_BRANCH="v0/agent/' "${test_dir}/.v0.profile.rc"
    assert_success
}

@test "v0_init_config writes user branch to .v0.profile.rc when auto-generated" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    init_mock_git_repo "${test_dir}"
    cd "${test_dir}" || return 1

    # Mock wk to avoid actual wk initialization
    wk() { echo "mock wk $*"; return 0; }
    export -f wk

    source_lib "v0-common.sh"

    v0_init_config "${test_dir}"

    # Should contain explicit V0_DEVELOP_BRANCH="v0/agent/*" in profile
    run grep 'V0_DEVELOP_BRANCH="v0/agent/' "${test_dir}/.v0.profile.rc"
    assert_success
    # .v0.rc should have a comment about profile and source line
    run grep '# V0_DEVELOP_BRANCH defined in .v0.profile.rc' "${test_dir}/.v0.rc"
    assert_success
    run grep 'source.*\.v0\.profile\.rc' "${test_dir}/.v0.rc"
    assert_success
}

@test "v0_init_config preserves existing v0/develop branch" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    init_mock_git_repo "${test_dir}"
    cd "${test_dir}" || return 1

    # Create v0/develop branch with a different commit
    git checkout -b "v0/develop"
    echo "develop content" > develop.txt
    git add develop.txt
    git commit -m "Develop commit"
    local develop_commit
    develop_commit=$(git rev-parse HEAD)
    git checkout main

    # Mock wk to avoid actual wk initialization
    wk() { echo "mock wk $*"; return 0; }
    export -f wk

    source_lib "v0-common.sh"

    # Run init
    v0_init_config "${test_dir}"

    # Verify v0/develop branch still points to same commit (was preserved)
    run git rev-parse "v0/develop"
    assert_output "${develop_commit}"
}

@test "v0_init_config respects existing .v0.profile.rc V0_DEVELOP_BRANCH" {
    local test_dir="${TEST_TEMP_DIR}/new-project"
    init_mock_git_repo "${test_dir}"
    cd "${test_dir}" || return 1

    # Create the branch that will be in .v0.profile.rc
    git checkout -b "v0/agent/existing-branch"
    git checkout main

    # Pre-create .v0.profile.rc with a specific branch
    cat > "${test_dir}/.v0.profile.rc" <<'EOF'
# v0 user profile (not committed - user-specific settings)
export V0_DEVELOP_BRANCH="v0/agent/existing-branch"
EOF

    # Mock wk to avoid actual wk initialization
    wk() { echo "mock wk $*"; return 0; }
    export -f wk

    source_lib "v0-common.sh"

    # Run init without --develop (should use existing profile)
    v0_init_config "${test_dir}"

    # Verify .v0.profile.rc still contains the original branch (not overwritten)
    run grep 'V0_DEVELOP_BRANCH="v0/agent/existing-branch"' "${test_dir}/.v0.profile.rc"
    assert_success

    # Verify no new branch was auto-generated in the profile
    run grep 'V0_DEVELOP_BRANCH="v0/agent/[a-z]*-[a-f0-9]' "${test_dir}/.v0.profile.rc"
    # This should match the existing-branch pattern, not a new random one
    refute_output --partial "-[a-f0-9][a-f0-9][a-f0-9][a-f0-9]"
}
