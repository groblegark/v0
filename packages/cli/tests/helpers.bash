#!/usr/bin/env bash
# Shared helpers for cli/tests/*.bats

# Helper: Initialize a git repo with a remote origin
init_git_repo_with_remote() {
    init_mock_git_repo "${TEST_TEMP_DIR}/project"
    cd "${TEST_TEMP_DIR}/project" || return 1
    git clone --bare . "${TEST_TEMP_DIR}/origin.git" 2>/dev/null
    git remote remove origin 2>/dev/null || true
    git remote add origin "${TEST_TEMP_DIR}/origin.git"
    git push -u origin "$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null
}

# Helper: Set up project with v0.rc, cd, source lib, and load config
setup_v0_project() {
    create_v0rc "${1:-project}" "${2:-prj}"
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"
    v0_load_config
}

# Helper: Set up git repo, cd, and source lib
setup_git_repo() {
    init_mock_git_repo "${1:-${TEST_TEMP_DIR}/project}"
    cd "${1:-${TEST_TEMP_DIR}/project}" || return 1
    source_lib "v0-common.sh"
}
